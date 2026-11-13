# A US mass-market paperback's UPC + 5-digit add-on as ISBNs (docs/
# CATALOG.md, "Scanning US mass-markets"). Many carry a retail UPC instead
# of an ISBN barcode: the UPC names only the publisher (digits 2–6) and the
# cover price, shared by every book at that price. The add-on is, by the
# publisher's convention, either ISBN-10 digits 5–9 (Tor: 0-8125-5010-2 →
# 55010) or its title part zero-padded (DAW: 0-88677-299-0 → 00299). What
# goes in front comes from the publisher, and there's no published table
# of UPC publisher codes, so it's learnt (UpcPrefix): each scan's
# mass-market candidates narrow the UPC publisher's possible ISBN prefixes
# until one is left — then the ISBN follows exactly. Until then every
# candidate is offered and Mark picks his by its cover.
class UpcLookup
  Result = Struct.new(:isbns, :prefixes, keyword_init: true) # isbns: ISBN-13s, most likely first; prefixes: the known ones used

  UPC = /\A\d{12}\z/
  ADD_ON = /\A\d{5}\z/
  PHYSICAL = %w[pb tp hc].freeze

  # "070999012345 30054", "070999012345+30054" — a scan or what's typed.
  def self.parse(text)
    m = text.to_s.strip.match(/\A(\d{12})\s*\+?\s*(\d{5})\z/) or return
    [ m[1], m[2] ]
  end

  def self.call(upc:, add_on:, client: ::Isfdb::Client.new) = new(client:).call(upc:, add_on:)

  def initialize(client:)
    @client = client
  end

  def call(upc:, add_on:)
    raise ArgumentError, "a 12-digit UPC and a 5-digit add-on" unless upc.match?(UPC) && add_on.match?(ADD_ON)

    printings = @client.isbns_for_addon(add_on).select { |p| english?(p) && physical?(p) }
    by_prefix = printings.group_by { |p| prefix_for(isbn10(p), add_on) }.except(nil)
    # Learnt only from mass-market printings: a UPC with an add-on is a
    # mass-market's, and a misread add-on (25011 for 55010 on a Tor,
    # 2026-11-08) usually matches only other formats, so it teaches nothing.
    mass_market = by_prefix.select { |_, ps| ps.any? { |p| p["binding"] == "pb" } }.keys
    known = learn(upc[1, 5], mass_market, all: by_prefix.keys)
    chosen = known.any? ? by_prefix.slice(*known) : by_prefix
    isbns = chosen.values.flatten.sort_by { |p| p["binding"] == "pb" ? 0 : 1 }.filter_map { |p| isbn13(p) }.uniq
    Result.new(isbns:, prefixes: known)
  end

  private

  # The publisher's known prefixes among this scan's candidates — or, if
  # none is (a new prefix for it, or none known yet), narrow its open
  # candidates by this scan's mass-market ones; one left joins the known.
  # A scan sharing nothing with the open candidates starts them afresh
  # rather than ruling everything out. -> the known prefixes to keep to.
  def learn(manufacturer, mass_market, all:)
    record = UpcPrefix.find_or_initialize_by(manufacturer:)
    # A fuller form of a known prefix is the same publisher: DAW is 0886
    # in LibraryThing's table, 0-88677 when its add-on is the title part
    # (Smuggler's Gold, 00299 — Mark checked the printed digits, 2026-11-13).
    hits = all.select { |p| record.known_prefixes.any? { |k| p.start_with?(k) || k.start_with?(p) } }
    return hits if hits.any?
    return [] if mass_market.empty?

    narrowed = record.candidates.presence ? (record.candidates & mass_market) : mass_market
    narrowed = mass_market if narrowed.empty?
    if narrowed.one?
      record.update!(candidates: [], known_prefixes: (record.known_prefixes | narrowed).sort)
      narrowed
    else
      record.update!(candidates: narrowed.sort)
      []
    end
  end

  # What stands in front of the add-on in this ISBN: its first four digits
  # when the add-on is digits 5–9 (Tor), else its publisher prefix when the
  # add-on is its title part (DAW).
  def prefix_for(isbn10, add_on)
    return unless isbn10
    return isbn10[0, 4] if isbn10[4, 5] == add_on

    prefix = Isbn.publisher_prefix(isbn10)
    prefix if prefix && isbn10[prefix.length...9].rjust(5, "0") == add_on
  end

  def english?(p) = p["language"].blank? || AddBook::EditionCards::ENGLISH.include?(p["language"].downcase)

  def physical?(p) = PHYSICAL.include?(p["binding"].to_s.downcase)

  def isbn10(p) = p["isbn_10"].presence || Isbn.to_10(p["isbn_13"].to_s)

  def isbn13(p) = p["isbn_13"].presence || Isbn.to_13(p["isbn_10"].to_s)
end
