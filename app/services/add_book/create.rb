module AddBook
  # Step 2 of adding a book (docs/CATALOG.md, "The two-step model"): build
  # the record from the chosen card's provider records, through the same
  # enrichment machinery as everything else — so an edition can be ISFDB +
  # Open Library the way older ones are Goodreads + ISFDB.
  #
  # The card's best record (ISFDB's when it has one) fills the new edition
  # via Enrichment::SourceRecorder — every field is empty, so it's all
  # fills and nothing to review. The card's other provider records are
  # kept as EnrichmentRecords beside it and fill only the gaps the best
  # one left (Open Library's cover for a printing ISFDB has no scan of):
  # where they differ, providers usually spell the same fact differently
  # ("Tor" / "Tom Doherty Associates"), and adding a book shouldn't fill
  # the review queue — the per-edition reconcile cog compares them
  # whenever wanted.
  class Create
    WORK_ID_TYPES = Search::WORK_ID_TYPES
    SEED_ISBNS = 3

    # `work`: the catalogue Work, or nil to create one from `found` (a
    # Search::Result-like hash: title, authors, first_year, cover_url,
    # provider_works [{provider, id, isbns}]).
    def self.want(work:, found:)
      Work.transaction do
        work ||= create_work(found)
        work.want || work.create_want!(seed_isbns: seed_isbns(found), cover_url: found&.dig("cover_url")).tap do |want|
          want.attach_cover_from_url(want.cover_url) if want.cover_url
          WantPrintingsJob.perform_later(want.id)
        end
      end
    end

    # The chosen card becomes an Edition (owned unless `own: false` — the
    # Copy behind it, EditionHolding — and with a Reading if `reading:` is
    # given) of `work`, or of a new work from `found`. `replaces:` an
    # edition Mark owned, which becomes "replaced" (the Goodreads edition
    # reconciliation's "change edition"). A want on the work is retired —
    # the book's been got — and its work kept.
    def self.edition(work:, found:, card:, own: true, replaces: nil, reading: nil)
      Work.transaction do
        work ||= create_work(found)
        edition = build_edition(work, card)
        copy = Copy.create!(edition:, disposition: "owned") if own
        EditionHolding.update(replaces, status: "replaced") if own && replaces
        if reading
          Reading.create!(work:, edition:, copy:, status: reading[:status], source: own ? "owned_copy" : reading[:source].presence || "other",
                          date_started: reading[:date_started], date_finished: reading[:date_finished], rating: reading[:rating])
        end
        work.want&.retire!(keep: work) if own
        [ work, edition ]
      end
    end

    def self.create_work(found)
      work = Work.create!(title: found.fetch("title"), literary_form: "novel",
                          original_publication_year: found["first_year"], field_sources: { "title" => primary_provider(found) })
      Array(found["authors"]).each_with_index do |name, i|
        contributor = Contributor.where("lower(name) = lower(?)", name).order(:id).first || Contributor.create!(name:)
        work.work_contributors.create!(contributor:, role: "author", display_order: i)
      end
      Array(found["provider_works"]).each do |pw|
        type = WORK_ID_TYPES[pw["provider"]] or next
        work.work_identifiers.find_or_create_by!(id_type: type, value: pw["id"].to_s) { |i| i.source = "add_book" }
      end
      work
    end

    def self.build_edition(work, card)
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      fill(edition, card)
    end

    # An edition with nothing on it takes the card: the best record
    # through SourceRecorder, the others beside it filling gaps, and the
    # card's identifiers. Also how EditionChange re-points an edition.
    def self.fill(edition, card)
      editions = card.map { |e| Providers::Edition.new(**e.symbolize_keys) }
      primary = EditionCards::Card.new(editions:).primary

      Enrichment::SourceRecorder.record(entity: edition, provider: primary.provider, external_id: primary.id,
                                        raw_payload: primary.to_h, fields: fields(primary))
      # One record per provider: other printings on the card from the
      # primary's own provider aren't another source.
      editions.reject { |e| e.provider == primary.provider }.uniq(&:provider).each do |other|
        all = fields(other)
        EnrichmentRecord.find_or_initialize_by(entity: edition, provider: other.provider)
                        .update!(external_id: other.id, fetched_at: Time.current, raw_payload: other.to_h,
                                 fields: all.except(:cover_image).stringify_keys)
        edition.reload
        gaps = all.select { |field, _| field == :cover_image ? !edition.cover_image.attached? : edition.public_send(field).blank? }
        Enrichment::SourceRecorder.record(entity: edition, provider: other.provider, external_id: other.id,
                                          raw_payload: other.to_h, fields: gaps)
      end
      record_identifiers(edition, [ primary ] + (editions - [ primary ])) # the record's printing names the edition
      edition.reload
    end

    def self.fields(e)
      format, format_detail = Enrichment::IsfdbEditionEnricher::FORMAT_BY_PTYPE[e.binding.to_s.downcase] if e.provider == "isfdb"
      format ||= { "paperback" => "paperback", "mass market paperback" => "paperback", "hardcover" => "hardcover",
                   "ebook" => "ebook" }[e.binding.to_s.downcase]
      format_detail ||= "mass_market" if e.binding.to_s.casecmp?("mass market paperback")
      {
        publisher: e.publisher.presence&.then { |p| Authority.resolve("publisher", p) || p },
        publish_date: (e.publish_date if e.publish_date.to_s.match?(Edition::PUBLISH_DATE_FORMAT)),
        page_count: e.page_count, language: e.language.presence, cover_artist: e.cover_artist.presence,
        format:, format_detail:, cover_image: e.cover_url.presence
      }.compact
    end

    def self.record_identifiers(edition, editions)
      ids = []
      if (isbn = editions.filter_map(&:isbn).first)
        ids << [ "isbn13", isbn ]
        ids << [ "isbn10", Isbn.to_10(isbn) ] if Isbn.to_10(isbn)
      end
      editions.each { |e| ids << [ e.provider, e.id.to_s ] if %w[isfdb openlibrary].include?(e.provider) }
      ids.uniq(&:first).each { |type, value| edition.edition_identifiers.create!(id_type: type, value:) }
    end

    def self.seed_isbns(found)
      Array(found&.dig("provider_works")).flat_map { |pw| Array(pw["isbns"]) }.uniq.first(SEED_ISBNS)
    end

    def self.primary_provider(found)
      providers = Array(found["provider_works"]).map { |pw| pw["provider"] }
      providers.include?("isfdb") ? "isfdb" : providers.first
    end
  end
end
