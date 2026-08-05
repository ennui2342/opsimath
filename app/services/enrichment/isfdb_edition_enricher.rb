require "net/http"

module Enrichment
  # Enriches one Edition from isfdb-adapter's /isbn/{isbn} endpoint —
  # deliberately edition-scoped, not work-scoped: that endpoint returns
  # edition-shaped data (publisher, publish date, page count, cover),
  # and its "description"/"categories" fields are hardcoded empty in the
  # adapter's own current implementation (confirmed directly against its
  # source and the live mirror — title_synopsis is a dangling reference
  # to a table refresh.py doesn't import), so there's nothing to enrich
  # at the Work level yet. /search's fuzzy title/author matching is
  # deliberately out of scope for v1 too — a real, harder problem, not
  # rushed in alongside this.
  class IsfdbEditionEnricher
    Result = Struct.new(:status, :message, keyword_init: true)

    # Only the pub_ptype values confirmed live against the real mirror
    # (2026-08-05, via a read-only query through the running adapter pod)
    # that map confidently onto our format/format_detail. The long tail
    # (webzine, quarto, octavo, A4, "unknown", ...) is either not a
    # physical book format at all or a print-size term neither our
    # format enum nor ONIX format_detail has room for — left unmapped
    # rather than guessed, same discipline as the Goodreads importer's
    # own Binding mapping.
    FORMAT_BY_PTYPE = {
      "hc" => [ "hardcover", nil ],
      "tp" => [ "paperback", nil ], # US/UK trade ambiguous — same call as the Goodreads importer's "Trade Paperback"
      "pb" => [ "paperback", "mass_market" ],
      "digest" => [ "paperback", nil ],
      "pulp" => [ "paperback", nil ],
      "ebook" => [ "ebook", nil ],
      "audio cd" => [ "audiobook", nil ],
      "digital audio download" => [ "audiobook", nil ],
      "audio mp3 cd" => [ "audiobook", nil ]
    }.freeze

    def self.enrich(edition, client: Isfdb::Client.new)
      new(edition, client: client).enrich
    end

    def initialize(edition, client:)
      @edition = edition
      @client = client
    end

    def enrich
      isbn = @edition.edition_identifiers.where(id_type: %w[isbn13 isbn10]).pick(:value)
      return Result.new(status: :skipped, message: "no isbn identifier") unless isbn

      data = @client.lookup_isbn(isbn)
      return Result.new(status: :skipped, message: "not found in isfdb mirror") unless data

      record_enrichment(data)
      apply_fields(data)
      backfill_isfdb_identifier(data)
      attach_cover(data)

      Result.new(status: :success)
    rescue Isfdb::ServiceError => e
      Result.new(status: :failed, message: e.message)
    end

    private

    def record_enrichment(data)
      EnrichmentRecord.create!(
        entity: @edition,
        provider: "isfdb",
        external_id: data["_isfdb_pub_id"].to_s,
        fetched_at: Time.current,
        raw_payload: data
      )
    end

    def apply_fields(data)
      FieldApplier.apply(@edition, :publisher, data["publisher"], "isfdb")
      FieldApplier.apply(@edition, :language, data["language"], "isfdb")
      FieldApplier.apply(@edition, :page_count, data["page_count"], "isfdb")
      apply_publish_date(data["publish_date"])
      apply_format(data["binding"])
    end

    # publish_date/publish_date_precision are one coupled fact, not two
    # independent fields — precision only ever gets (re)written alongside
    # a date that was actually just filled in, never against an existing
    # or conflicting date it wouldn't describe correctly.
    def apply_publish_date(raw)
      return if raw.blank?

      date, precision = parse_isfdb_date(raw)
      return unless date

      result = FieldApplier.apply(@edition, :publish_date, date, "isfdb")
      @edition.update!(publish_date_precision: precision) if result.status == :applied
    end

    def parse_isfdb_date(raw)
      case raw
      when /\A(\d{4})-(\d{2})-(\d{2})\z/ then [ Date.new($1.to_i, $2.to_i, $3.to_i), "day" ]
      when /\A(\d{4})-(\d{2})\z/ then [ Date.new($1.to_i, $2.to_i, 1), "month" ]
      when /\A(\d{4})\z/ then [ Date.new($1.to_i, 1, 1), "year" ]
      end
    end

    def apply_format(raw_ptype)
      format, format_detail = FORMAT_BY_PTYPE[raw_ptype.to_s.downcase]
      return unless format

      FieldApplier.apply(@edition, :format, format, "isfdb")
      FieldApplier.apply(@edition, :format_detail, format_detail, "isfdb") if format_detail
    end

    def backfill_isfdb_identifier(data)
      return if data["_isfdb_pub_id"].blank?

      EditionIdentifier.find_or_create_by!(edition: @edition, id_type: "isfdb", value: data["_isfdb_pub_id"].to_s)
    end

    # Downloaded and kept, not hotlinked (DATA_MODEL.md's Edition.cover_image
    # note) — an ISFDB cover URL can and does go stale over time. Failure
    # here is logged, not raised: a missing cover shouldn't block the
    # fields above from being applied.
    def attach_cover(data)
      return if @edition.cover_image.attached?

      url = data["cover_url"]
      return if url.blank?

      uri = URI.parse(url)
      return unless %w[http https].include?(uri.scheme)

      response = Net::HTTP.get_response(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      @edition.cover_image.attach(
        io: StringIO.new(response.body),
        filename: File.basename(uri.path).presence || "cover.jpg",
        content_type: response.content_type || "image/jpeg"
      )
    rescue StandardError => e
      Rails.logger.warn("isfdb cover download failed for edition #{@edition.id}: #{e.message}")
    end
  end
end
