# A US mass-market paperback's UPC + 5-digit add-on as ISBNs (docs/
# CATALOG.md, "Scanning US mass-markets"). Many carry a retail UPC instead
# of an ISBN barcode: the UPC names only the publisher (digits 2–6) and the
# cover price, shared by every book at that price; the add-on is digits
# 5–9 of the book's ISBN-10. The first four come from the publisher, and
# there's no published table of those, so they're learnt (UpcPrefix): each
# scan's English physical printings with that middle narrow the UPC
# publisher's possible prefixes until one is left. Until then every
# candidate is offered and Mark picks his by its cover.
class UpcLookup
  Result = Struct.new(:isbns, :prefix, keyword_init: true) # isbns: ISBN-13s, most likely first

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

    printings = @client.isbns_with_middle(add_on).select { |p| english?(p) && physical?(p) }
    by_prefix = printings.group_by { |p| isbn10(p)&.first(4) }.except(nil)
    known = learn(upc[1, 5], by_prefix.keys)
    chosen = known ? by_prefix.slice(known) : by_prefix
    isbns = chosen.values.flatten.sort_by { |p| p["binding"] == "pb" ? 0 : 1 }.filter_map { |p| isbn13(p) }.uniq
    Result.new(isbns:, prefix: known)
  end

  private

  # Narrow the publisher's possible prefixes by this scan's; one left is
  # its prefix. A scan that shares none (a printing ISFDB lacks) starts
  # the candidates afresh rather than ruling everything out.
  def learn(manufacturer, prefixes)
    return if prefixes.empty?

    record = UpcPrefix.find_or_initialize_by(manufacturer:)
    return record.prefix if record.prefix && prefixes.include?(record.prefix)

    narrowed = record.candidates.presence ? (record.candidates & prefixes) : prefixes
    narrowed = prefixes if narrowed.empty?
    record.update!(candidates: narrowed.sort, prefix: (narrowed.first if narrowed.one?))
    record.prefix
  end

  def english?(p) = p["language"].blank? || AddBook::EditionCards::ENGLISH.include?(p["language"].downcase)

  def physical?(p) = PHYSICAL.include?(p["binding"].to_s.downcase)

  def isbn10(p) = p["isbn_10"].presence || Isbn.to_10(p["isbn_13"].to_s)

  def isbn13(p) = p["isbn_13"].presence || Isbn.to_13(p["isbn_10"].to_s)
end
