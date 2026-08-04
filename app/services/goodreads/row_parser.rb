module Goodreads
  # Pure parsing/normalization helpers for one row of a Goodreads library
  # export CSV. No database access — see docs/INTEGRATIONS.md for the
  # column mapping this implements and the real-data checks behind each
  # rule (confirmed against import/goodreads_library_export_enriched.csv,
  # not invented).
  module RowParser
    STATUS_SHELVES = %w[to-read currently-reading read did-not-finish wishlist].freeze

    # Goodreads' CSV export wraps ISBN-like columns in an Excel
    # formula-escape (`="0425038521"`) to stop spreadsheet apps from
    # stripping leading zeros. Confirmed on real rows — blank is `=""`.
    def self.clean_isbn(raw)
      cleaned = raw.to_s.delete_prefix('="').delete_suffix('"')
      cleaned.presence
    end

    # Collapses the doubled/tripled internal whitespace real rows contain
    # (e.g. "Keith       Roberts") without attempting to split garbled
    # multi-author fields ("Larry & Jerry Niven & Pournelle") or Goodreads
    # slug artifacts ("delany-samuel-r") — those are real data-quality
    # issues in the export, left as-is for manual Contributor cleanup
    # later rather than guessed at automatically.
    def self.clean_name(raw)
      raw.to_s.gsub(/\s+/, " ").strip.presence
    end

    def self.additional_authors(raw)
      raw.to_s.split(",").map { |n| clean_name(n) }.compact
    end

    # Goodreads is 0-5 whole stars; "0" means unrated, not zero-star.
    # opsimath's scale is already 0-5 half-star, so this is a direct
    # passthrough once "0" is treated as nil — no conversion needed.
    def self.rating(raw)
      value = raw.to_s.strip
      return nil if value.empty? || value.to_f.zero?

      value.to_f
    end

    FORMAT_BY_BINDING = {
      "paperback" => [ "paperback", nil ],
      "mass market paperback" => [ "paperback", "mass_market" ],
      "trade paperback" => [ "paperback", nil ],
      "perfect paperback" => [ "paperback", nil ],
      "spiral-bound" => [ "paperback", nil ],
      "paper" => [ "paperback", nil ],
      "hardcover" => [ "hardcover", nil ],
      "kindle edition" => [ "ebook", nil ],
      "ebook" => [ "ebook", nil ],
      "audiobook" => [ "audiobook", nil ],
      "audio cd" => [ "audiobook", nil ]
    }.freeze

    # Falls back to paperback (the real export's overwhelming majority
    # format) for "Unknown Binding"/"unknown"/blank — a cheap default to
    # hand-correct later per PHILOSOPHY.md principle 6, not a guess
    # dressed up as data.
    def self.format_and_detail(binding_value)
      FORMAT_BY_BINDING.fetch(binding_value.to_s.strip.downcase, [ "paperback", nil ])
    end

    DATE_SLASH = /\A(\d{4})\/(\d{2})\/(\d{2})\z/
    DATE_DASH = /\A(\d{4})-(\d{2})-(\d{2})\z/

    def self.parse_date_slash(raw)
      m = DATE_SLASH.match(raw.to_s.strip)
      m && Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
    end

    def self.parse_date_dash(raw)
      m = DATE_DASH.match(raw.to_s.strip)
      m && Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
    end

    ReadEvent = Struct.new(:date_started, :date_finished, keyword_init: true)

    # read_dates is definitive when present (semicolon-separated
    # start,end pairs, YYYY-MM-DD) — one real read-through per pair.
    # Read Count is never consulted; confirmed spurious for this library
    # (see docs/INTEGRATIONS.md). Blank read_dates always yields exactly
    # one event (the ordinary single-read case), using Date Read
    # (YYYY/MM/DD — a different format from read_dates, confirmed by
    # direct inspection) as date_finished, blank if that's missing too —
    # not a flagged gap, per the doc's explicit policy.
    def self.read_events(read_dates_raw, date_read_raw)
      pairs = read_dates_raw.to_s.split(";").map(&:strip).reject(&:empty?)
      return [ ReadEvent.new(date_started: nil, date_finished: parse_date_slash(date_read_raw)) ] if pairs.empty?

      pairs.map do |pair|
        start_raw, finish_raw = pair.split(",", 2)
        ReadEvent.new(date_started: parse_date_dash(start_raw), date_finished: parse_date_dash(finish_raw))
      end
    end

    SeriesInfo = Struct.new(:title, :series_name, :position, keyword_init: true)

    # Goodreads embeds series info in Title ("Neuromancer (Sprawl #1)").
    # Ported from goodreads-librarium-read-sync.yaml's proven heuristic:
    # find " (", treat it as a series suffix only if the remainder
    # contains "#" (a genuinely parenthetical title — a date, a
    # publisher name — doesn't). The raw title isn't kept as a
    # WorkAlternateTitle; it's a Goodreads UI display convention, not a
    # real alternate title a publisher used.
    def self.series_info(title)
      idx = title.to_s.index(" (")
      return SeriesInfo.new(title: title.to_s.strip, series_name: nil, position: nil) unless idx

      rest = title[(idx + 2)..]
      return SeriesInfo.new(title: title.strip, series_name: nil, position: nil) unless rest&.include?("#")
      return SeriesInfo.new(title: title.strip, series_name: nil, position: nil) unless rest.rstrip.end_with?(")")

      base = title[0...idx].strip
      paren = rest.rstrip.delete_suffix(")")
      # Series name/position: "Great Ship, #1", "The Fall Revolution #2",
      # "A Song of Ice and Fire, #5, Part 1 of 2" (trailing text after the
      # position is discarded), "Vorkosigan Saga, #4-5" (a range —
      # position takes the first number; good enough for ordering, not
      # pretending to model omnibus ranges precisely).
      m = /\A(.*?)\s*,?\s*#\s*([\d.]+)/.match(paren)
      return SeriesInfo.new(title: base, series_name: nil, position: nil) unless m

      SeriesInfo.new(title: base, series_name: m[1].strip, position: m[2].to_f)
    end

    # Bookshelves (plural) minus the status shelves already covered by
    # Exclusive Shelf — everything left is a candidate Genre/Tag label.
    def self.extra_shelves(bookshelves_raw)
      bookshelves_raw.to_s.split(",").map { |s| s.strip }.reject { |s| s.empty? || STATUS_SHELVES.include?(s) }
    end
  end
end
