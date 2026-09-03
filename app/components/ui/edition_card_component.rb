module Ui
  # One edition, laid out the same way everywhere it appears: cover on the
  # left, then a bold format line, an ownership lozenge, a muted
  # `publisher · year · pages` meta line, and a mono identifier footer —
  # ISBNs on one row, ISFDB/Goodreads (hyperlinked) on the next. The
  # pocket app (docs/MOBILE.md) renders the identical shape in plain
  # JS/CSS — see docs/DESIGN_SYSTEM.md "Edition card" for the shared spec.
  class EditionCardComponent < ApplicationComponent
    def initialize(edition:)
      @edition = edition
    end

    # format_detail is the specific one ("mass market"); format is the
    # coarse fallback ("paperback"); "Edition" when the feed gave neither.
    def format_line
      (@edition.format_detail || @edition.format)&.humanize || "Edition"
    end

    def meta_line
      [
        @edition.publisher.presence,
        @edition.publish_date&.slice(0, 4),
        ("#{@edition.page_count} pages" if @edition.page_count)
      ].compact_blank.join(" · ")
    end

    # [label, variant] for the ownership lozenge, or nil for a catalogue-only
    # edition (no copy has ever passed through). An owned copy wins over a
    # retired one when an edition somehow has both.
    def status_badge
      dispositions = @edition.copies.map(&:disposition)
      return nil if dispositions.empty?

      return [ "Owned", :success ] if dispositions.include?("owned")

      [ Copy::DISPOSITION_LABELS.fetch(dispositions.first, dispositions.first.humanize), :default ]
    end

    # The mono footer, split into two rows so it wraps cleanly:
    # ISBNs first, then the linkable ids. Each entry is [label, value, url].
    def isbn_identifiers = identifier_rows.select { |_, _, url| url.nil? }
    def link_identifiers = identifier_rows.reject { |_, _, url| url.nil? }

    def cover_variant
      @edition.cover_image.variant(:thumb) if @edition.cover_image.attached?
    end

    private

    def identifier_rows
      @identifier_rows ||= EditionIdentifier.for_display(@edition.edition_identifiers).map do |identifier|
        [ identifier.label, identifier.value, identifier.external_url ]
      end
    end
  end
end
