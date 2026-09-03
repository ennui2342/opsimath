module Ui
  # One edition, laid out the same way everywhere it appears: cover on the
  # left, then a bold format line, a muted `publisher · year · pages`
  # meta line, and a mono identifier footer with ISFDB/Goodreads
  # hyperlinked. The pocket app (docs/MOBILE.md) renders the identical
  # shape in plain JS/CSS — see docs/DESIGN_SYSTEM.md "Edition card" for
  # the shared spec the two implementations track.
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

    # [[label, value, external_url_or_nil], ...] in EditionIdentifier's
    # canonical order.
    def identifiers
      EditionIdentifier.for_display(@edition.edition_identifiers).map do |identifier|
        [ identifier.label, identifier.value, identifier.external_url ]
      end
    end

    def cover_variant
      @edition.cover_image.variant(:thumb) if @edition.cover_image.attached?
    end
  end
end
