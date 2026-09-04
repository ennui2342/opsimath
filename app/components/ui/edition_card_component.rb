module Ui
  # One edition, laid out the same way everywhere it appears: cover on the
  # left, then — in this order — a bold headline (`publisher · year ·
  # pages`), a lozenge row (ownership + reading status), a muted
  # `format · cover artist` line, and a mono identifier footer — ISBNs on
  # one row, ISFDB/Goodreads (hyperlinked) on the next. The pocket app
  # (docs/MOBILE.md) renders the identical shape in plain JS/CSS — see
  # docs/DESIGN_SYSTEM.md "Edition card" for the shared spec.
  class EditionCardComponent < ApplicationComponent
    def initialize(edition:)
      @edition = edition
    end

    # The bold top line — what most distinguishes one printing from
    # another at a glance. Falls back to format_line so a bare stub
    # edition (no publisher/date/pages yet) still gets a real headline
    # rather than going blank.
    def headline
      [
        @edition.publisher.presence,
        @edition.publish_date&.slice(0, 4),
        ("#{@edition.page_count} pages" if @edition.page_count)
      ].compact_blank.join(" · ").presence || format_line
    end

    # format_detail is the specific one ("mass market"); format is the
    # coarse fallback ("paperback"); "Edition" when the feed gave neither.
    def format_line
      (@edition.format_detail || @edition.format)&.humanize || "Edition"
    end

    def artist = @edition.cover_artist.presence

    # The muted line under the lozenges — format, plus the cover artist
    # when ISFDB credits one (edition-level data; Goodreads never has it).
    def detail_line = [ format_line, artist ].compact_blank.join(" · ")

    # The lozenge row: ownership (Owned/Replaced/…) and reading status
    # (Reading/Read/DNF/TBR), independent of each other — a library read
    # has no ownership lozenge, a fresh unread purchase has no reading one
    # only once it's genuinely "mine" in some sense (see #reading_badge).
    def status_badges = [ ownership_badge, reading_badge ].compact

    # [label, variant] for the ownership lozenge, or nil for a catalogue-only
    # edition (no copy has ever passed through). An owned copy wins over a
    # retired one when an edition somehow has both.
    def ownership_badge
      dispositions = @edition.copies.map(&:disposition)
      return nil if dispositions.empty?

      return [ "Owned", :success ] if dispositions.include?("owned")

      [ Copy::DISPOSITION_LABELS.fetch(dispositions.first, dispositions.first.humanize), :default ]
    end

    # [label, variant] for where this edition stands in your reading —
    # nil when there's genuinely nothing to say (a catalogue-only
    # alternate you've never owned or read; showing "TBR" there would
    # claim an intent you don't have). An open (or paused) reading wins
    # over a past completed one, which wins over a DNF; with a copy or a
    # reading on file but none of those, it's TBR.
    #
    # :accent (Reading) / :info (Read) — deliberately not :default/:success:
    # this is a reading fact, not an ownership one, and :success is
    # ownership_badge's own color for "Owned" — the two used to collide
    # visually right next to each other on the same card. DNF/TBR stay
    # :default (nothing currently happening).
    def reading_badge
      return nil if @edition.copies.empty? && @edition.readings.empty?

      statuses = @edition.readings.map(&:status)
      return [ "Reading", :accent ] if statuses.intersect?(%w[reading paused])
      return [ "Read", :info ] if statuses.include?("completed")
      return [ "DNF", :default ] if statuses.include?("dnf")

      [ "TBR", :default ]
    end

    # The mono footer, split into two rows so it wraps cleanly:
    # ISBNs first, then the linkable ids. Each entry is [label, value, url].
    def isbn_identifiers = identifier_rows.select { |_, _, url| url.nil? }
    def link_identifiers = identifier_rows.reject { |_, _, url| url.nil? }

    def cover_variant
      @edition.cover_image.variant(:thumb) if @edition.cover_image.attached?
    end

    # Every known source that has a cover on file — the right-click "pick a
    # different cover" panel's options. One row per provider
    # (EnrichmentRecord's own uniqueness), so this is at most a couple of
    # entries (goodreads/isfdb) in practice.
    def cover_choices
      @edition.enrichment_records.select { |r| r.cover_image.attached? }
    end

    private

    def identifier_rows
      @identifier_rows ||= EditionIdentifier.for_display(@edition.edition_identifiers).map do |identifier|
        [ identifier.label, identifier.value, identifier.external_url ]
      end
    end
  end
end
