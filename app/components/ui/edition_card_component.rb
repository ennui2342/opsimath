module Ui
  # One edition, laid out the same way everywhere it appears: cover on the
  # left, then — in this order — a bold headline (`publisher · year ·
  # pages`), a lozenge row (ownership + reading status), a muted
  # `format · cover artist` line, and a mono identifier footer — ISBNs on
  # one row, ISFDB/Goodreads (hyperlinked) on the next. The pocket app
  # (docs/MOBILE.md) renders the identical shape in plain JS/CSS — see
  # docs/DESIGN_SYSTEM.md "Edition card" for the shared spec.
  #
  # Three sizes, one card (Mark, 2026-11-08: "change the card and it will
  # update everywhere"): `:full` on the book page; `:row`, the compressed
  # card for any list of Mark's editions (author, series, publisher pages,
  # the Books list) — smaller cover, the book's title and credited author,
  # headline, detail line and lozenges, no identifiers or cog; `:tile`, the
  # same parts cover-first for a grid (artist, line pages). Books not in the
  # catalogue use Ui::BookCandidateCardComponent, built to the same shape.
  class EditionCardComponent < ApplicationComponent
    include CardNumber

    SIZES = %i[full row tile].freeze

    # `publisher_url:` (web book page): the publisher in the headline links
    # to its page. Same text either way — the pocket app's twin is unaffected.
    # `work:` the book it's listed as (an omnibus edition is in several);
    # `number:` a leading "#3" / year in a row; `context_author:` the
    # page's own author, whose name the author line leaves out.
    def initialize(edition:, publisher_url: nil, size: :full, work: nil, number: nil, context_author: nil)
      raise ArgumentError, "size: #{size}" unless SIZES.include?(size)

      @edition = edition
      @publisher_url = publisher_url
      @size = size
      @work = work || edition.works.first
      @number = number
      @context_author = context_author
    end

    def full? = @size == :full
    def row? = @size == :row

    def title = @work&.title || "Edition ##{@edition.id}"

    def work_url = @work && helpers.work_path(@work)

    # Who this edition credits: its ISFDB printing's credit where ISFDB
    # records one (a pseudonym — "Richard Bachman (Stephen King)" — when it
    # isn't the book's author), else the book's authors. nil when it would
    # only repeat the page's own author.
    def author_line
      book = Array(@work&.authors).map(&:name)
      credited = printing&.author_names.presence || book
      pseudonymous = book.any? && credited.map { |n| Authority.normalize(n) }.sort != book.map { |n| Authority.normalize(n) }.sort
      return if !pseudonymous && @context_author && credited.map { |n| Authority.normalize(n) } == [ Authority.normalize(@context_author) ]

      line = self.class.names(credited)
      pseudonymous ? "#{line} (#{self.class.names(book)})" : line.presence
    end

    # "A, B, C" — or "A, B, C and 4 others" for an anthology's list.
    def self.names(list)
      list.size > 3 ? "#{list.first(3).join(', ')} and #{list.size - 3} others" : list.join(", ")
    end

    # Compact headline for a row or tile: publisher · year.
    def short_headline = [ @edition.publisher.presence, @edition.publish_date&.slice(0, 4) ].compact.join(" · ").presence || format_line

    # The headline with its publisher linked, when there's a link to give.
    def headline_html
      return headline unless @publisher_url && @edition.publisher.present?

      rest = headline.delete_prefix(@edition.publisher)
      helpers.safe_join([ helpers.link_to(@edition.publisher, @publisher_url, class: "hover:underline"), rest ])
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

    # The ISFDB printing this edition is (its `isfdb` identifier), from the
    # book's known printings.
    def printing
      return @printing if defined?(@printing)

      # Only from printings already loaded: the Books list (every book)
      # doesn't load them, and shows the book's authors instead.
      pub = @edition.edition_identifiers.find { |i| i.id_type == "isfdb" }&.value
      loaded = @work&.association(:provider_editions)&.loaded?
      @printing = pub && loaded ? @work.provider_editions.find { |p| p.provider == "isfdb" && p.provider_id == pub } : nil
    end

    def identifier_rows
      @identifier_rows ||= EditionIdentifier.for_display(@edition.edition_identifiers).map do |identifier|
        [ identifier.label, identifier.value, identifier.external_url ]
      end
    end
  end
end
