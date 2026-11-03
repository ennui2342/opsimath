module Mobile
  # The denormalised "shop view" of the collection: one flat list of
  # entries, each a book you own or have wishlisted, carrying everything
  # the offline lookup PWA needs to answer "owned / wishlisted / neither"
  # for a book in hand (docs/MOBILE.md constraint 3).
  #
  # A single searchable unit deliberately: a catalogued work and an
  # unmatched wishlist item both become an `Entry`, so the client runs one
  # search / one barcode lookup, not one per collection. A work's
  # one-to-many editions hang off its entry (`editions`) and are joined
  # only after a hit, never searched.
  #
  # Format-agnostic plain data — Mobile::SnapshotBuilder turns it into
  # snapshot.sqlite3; the same shape is the natural basis for a public API.
  # "Do I own an edition of this work" and "is this work wishlisted" each
  # resolve in one query, not a per-work check.
  class ShopView
    Entry = Struct.new(
      :id,               # "work:<id>" / "wishlist:<id>" — unique within a snapshot
      :kind,             # "work" | "wishlist"
      :title, :subtitle, :authors, :series, :series_position, :original_year,
      :owned, :wishlisted,
      :isbn10, :isbn13, :goodreads, :has_cover, # entry-level — set only for kind "wishlist"
      :editions,                    # [Edition] — set only for kind "work"
      :want,                        # WantPrices — set when the book is wanted
      keyword_init: true
    )
    # A wanted book's bargain-hunting picture for the shop (docs/MOBILE.md,
    # "Prices"): its target, the collecting rule's verdict, and the covers
    # the rule offers with what each sells for on eBay — so a printing in
    # hand can be judged against its own cover's going rate.
    WantPrices = Struct.new(:target_pence, :rule, :covers, keyword_init: true)
    # median/count/cheapest over the cover's live listings, dismissed ones
    # included (Finds: dismissing is "not that copy", not a market change).
    CoverPrice = Struct.new(:id, :summary, :artists, :favourite, :chosen, :median_pence, :listing_count, :cheapest_pence,
                            :isbns, keyword_init: true)
    Edition = Struct.new(
      :id, :format, :format_detail, :publisher, :year, :page_count, :disposition,
      :cover_artist, :reading_status,
      :isbn10, :isbn13, :isfdb, :goodreads, :has_cover,
      keyword_init: true
    )
    Result = Struct.new(:entries, keyword_init: true)

    def self.build = new.build

    def build
      Result.new(entries: (work_entries + wishlist_entries).sort_by { |e| e.title.to_s.downcase })
    end

    private

    def work_entries
      owned = owned_work_ids
      wishlisted = wishlisted_work_ids

      work_scope.where(id: owned | wishlisted).find_each.map do |work|
        build_work_entry(work, owned:, wishlisted:)
      end
    end

    def work_scope
      ::Work.includes(
        { work_contributors: :contributor },
        { work_series: :series },
        { want: { work: [ :provider_editions, :ebay_listings, { work_contributors: :contributor } ] } },
        { editions: [ :edition_identifiers, :copies, :readings, { cover_image_attachment: :blob } ] }
      )
    end

    def build_work_entry(work, owned:, wishlisted:)
      first_series = work.work_series.min_by { |ws| ws.position || Float::INFINITY }

      Entry.new(
        id: "work:#{work.id}",
        kind: "work",
        title: work.title,
        subtitle: work.subtitle.presence,
        authors: authors_of(work),
        series: first_series&.series&.name,
        series_position: first_series&.position && format("%g", first_series.position),
        original_year: work.original_publication_year,
        owned: owned.include?(work.id),
        wishlisted: wishlisted.include?(work.id),
        editions: editions_of(work),
        want: work.want && want_prices(work.want)
      )
    end

    def profile = @profile ||= CollectingProfile.current

    def want_prices(want)
      view = WishlistItemView.new(want, profile:)
      covers = view.hunted? ? view.covers : []
      WantPrices.new(
        target_pence: want.target_price, rule: view.verdict.rule.to_s,
        covers: covers.map do |cover|
          totals = cover.priced.filter_map(&:total)
          CoverPrice.new(id: cover.id.to_s, summary: cover.summary, artists: cover.artists, favourite: cover.favourite,
                         chosen: cover.chosen, median_pence: Finds.median(totals)&.round, listing_count: totals.size,
                         cheapest_pence: totals.min, isbns: cover.printings.filter_map(&:isbn).uniq)
        end
      )
    end

    def authors_of(work)
      work.work_contributors
          .select { |wc| wc.role == "author" }
          .sort_by { |wc| wc.display_order || Float::INFINITY }
          .map { |wc| wc.contributor.name }
    end

    # Every edition of this work that a copy has passed through — owned
    # ones plus the retired ones (`replaced`/`sold`/…), so the shop card
    # can show which printing you hold now and which you used to.
    # `disposition` per edition carries that, and each edition (owned or
    # retired) is scannable via `isbn_index` (see SnapshotBuilder#isbn_rows).
    # Owned first, then by id. A wishlisted-only work has no edition rows.
    def editions_of(work)
      work.editions
          .select { |e| e.copies.any? }
          .sort_by { |e| [ owned?(e) ? 0 : 1, e.id ] }
          .map { |edition| build_edition(edition) }
    end

    def owned?(edition) = edition.copies.any? { |c| c.disposition == "owned" }

    # An edition with a mix of copies reads as owned if any copy is; else
    # it takes the disposition of its (single, realistically) retired copy.
    def disposition_of(edition)
      return "owned" if owned?(edition)

      edition.copies.first&.disposition
    end

    # Same precedence as Ui::EditionCardComponent#reading_badge on the
    # web (docs/DESIGN_SYSTEM.md) — reading/paused beats a past completed
    # read, which beats dnf; "tbr" (not nil) when there's simply no
    # Reading yet, since every edition reaching here already has a copy
    # (editions_of filters to that), unlike the web component's bare
    # catalogue-only nil case.
    def reading_status_of(edition)
      statuses = edition.readings.map(&:status)
      return "reading" if statuses.intersect?(%w[reading paused])
      return "read" if statuses.include?("completed")
      return "dnf" if statuses.include?("dnf")

      "tbr"
    end

    def build_edition(edition)
      ids = edition.edition_identifiers.each_with_object({}) { |i, h| h[i.id_type] = i.value }

      Edition.new(
        id: edition.id,
        format: edition.format,
        format_detail: edition.format_detail,
        publisher: edition.publisher.presence,
        year: edition.publish_date&.slice(0, 4),
        page_count: edition.page_count,
        disposition: disposition_of(edition),
        cover_artist: edition.cover_artist.presence,
        reading_status: reading_status_of(edition),
        isbn10: ids["isbn10"],
        isbn13: ids["isbn13"],
        isfdb: ids["isfdb"],
        goodreads: ids["goodreads"],
        has_cover: edition.cover_image.attached?
      )
    end

    # A wanted book you don't own: its own "wishlist" entry, scannable by
    # the ISBN it was wanted under. (Wanted *and* owned — an upgrade hunt —
    # is the owned work's entry, flagged wishlisted.)
    def wishlist_entries
      Want.where.not(work_id: owned_work_ids.to_a)
          .includes({ work: [ { work_contributors: :contributor }, { work_series: :series }, :provider_editions, :ebay_listings ] },
                    cover_image_attachment: :blob)
          .find_each.map do |want|
        isbn13 = want.seed_isbns.first
        Entry.new(
          id: "wishlist:#{want.id}",
          kind: "wishlist",
          title: want.title,
          authors: authors_of(want.work),
          series: want.work.work_series.min_by { |ws| ws.position || Float::INFINITY }&.series&.name,
          original_year: nil,
          owned: false,
          wishlisted: true,
          isbn10: isbn13 && Isbn.to_10(isbn13),
          isbn13:,
          goodreads: want.external_ids["goodreads"],
          has_cover: want.cover_image.attached?,
          editions: [],
          want: want_prices(want)
        )
      end
    end

    def owned_work_ids
      EditionContent
        .where(edition_id: Copy.where(disposition: "owned").select(:edition_id))
        .distinct.pluck(:work_id).to_set
    end

    def wishlisted_work_ids
      Want.where(work_id: owned_work_ids.to_a).pluck(:work_id).to_set
    end
  end
end
