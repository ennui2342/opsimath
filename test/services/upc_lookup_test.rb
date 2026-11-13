require "test_helper"

class UpcLookupTest < ActiveSupport::TestCase
  setup do
    @isfdb = ENV.fetch("ISFDB_ADAPTER_URL")
  end

  # A valid ISBN-10 from its first nine digits.
  def isbn10(first9)
    check = (11 - first9.chars.each_with_index.sum { |d, i| (10 - i) * d.to_i } % 11) % 11
    first9 + (check == 10 ? "X" : check.to_s)
  end

  def pub(first9, binding: "pb", language: "eng")
    i = isbn10(first9)
    { "isbn_10" => i, "isbn_13" => Isbn.to_13(i), "binding" => binding, "language" => language }
  end

  def middle(digits, *pubs) = stub_request(:get, "#{@isfdb}/isbn/addon/#{digits}").to_return(status: 200, body: pubs.to_json)

  test "parses a scanned or typed UPC and add-on" do
    assert_equal %w[070999012346 57636], UpcLookup.parse("070999012346 57636")
    assert_equal %w[070999012346 57636], UpcLookup.parse("070999012346+57636")
    assert_nil UpcLookup.parse("9780812576368")
    assert_nil UpcLookup.parse("070999012346")
  end

  test "the add-on's printings, English and physical; the UPC publisher's prefix learnt as scans narrow it" do
    tor = pub("081257636")                       # Tor 0-812
    ace = pub("044157636")                       # Ace 0-441, the same middle digits
    middle("57636", tor, ace, pub("281257636", language: "fre"), pub("181257636", binding: "ebook"))

    first = UpcLookup.call(upc: "080999012346", add_on: "57636")
    assert_equal [ tor["isbn_13"], ace["isbn_13"] ].sort, first.isbns.sort
    assert_empty first.prefixes
    assert_equal %w[0441 0812], UpcPrefix.find_by!(manufacturer: "80999").candidates

    middle("12345", pub("081212345"), pub("034512345")) # a second Tor book: only 0812 is in both
    second = UpcLookup.call(upc: "080999099990", add_on: "12345")
    assert_equal %w[0812], second.prefixes
    assert_equal [ Isbn.to_13(isbn10("081212345")) ], second.isbns

    middle("57636", tor, ace)
    assert_equal [ tor["isbn_13"] ], UpcLookup.call(upc: "080999012346", add_on: "57636").isbns # known now
  end

  test "only mass-market printings teach the prefix: a misread add-on matching trade paperbacks teaches nothing" do
    middle("25011", pub("082025011", binding: "tp"), pub("125025011", binding: "tp"))

    result = UpcLookup.call(upc: "087145005997", add_on: "25011")
    assert_equal 2, result.isbns.size # still offered
    assert_not UpcPrefix.exists?(manufacturer: "87145")
  end

  test "a scan sharing no prefix with what's known so far starts afresh rather than ruling everything out" do
    UpcPrefix.create!(manufacturer: "80999", candidates: %w[0812 0441])
    middle("11111", pub("055311111"))

    assert_equal %w[0553], UpcLookup.call(upc: "080999011111", add_on: "11111").prefixes
  end

  test "Add a book searches a UPC with its add-on like an ISBN" do
    tangled = pub("081257636")
    middle("57636", tangled)
    stub_request(:get, "#{@isfdb}/isbn/#{tangled["isbn_13"]}?all=true").to_return(status: 200, body: [
      { "_isfdb_pub_id" => 1, "_isfdb_title_id" => 20924, "title" => "Tangled Up in Blue", "authors" => [ "Joan D. Vinge" ],
        "isbn_13" => tangled["isbn_13"], "isbn_10" => tangled["isbn_10"], "binding" => "pb", "language" => "eng", "publisher" => "Tor" }
    ].to_json)

    results = AddBook::Search.run("070999012346 57636", providers: [ Providers::Isfdb.new ])

    assert_equal [ "Tangled Up in Blue" ], results.map(&:title)
  end

  test "DAW's add-on is the ISBN's title part zero-padded; its real prefix is learnt" do
    smugglers = pub("088677299")                 # DAW 0-88677-299-0, add-on 00299
    avon = pub("038000299")                      # Avon 0-380-00299-X: digits 5-9 are 00299 too
    middle("00299", smugglers, avon)

    first = UpcLookup.call(upc: "081125003504", add_on: "00299")
    assert_equal [ smugglers["isbn_13"], avon["isbn_13"] ].sort, first.isbns.sort
    assert_equal %w[0380 088677], UpcPrefix.find_by!(manufacturer: "81125").candidates

    middle("00300", pub("088677300"), pub("044100300"))  # another DAW book
    assert_equal %w[088677], UpcLookup.call(upc: "081125003511", add_on: "00300").prefixes
  end

  test "the publisher prefix of an English-group ISBN-10 follows its range" do
    assert_equal "088677", Isbn.publisher_prefix("0886772990")
    assert_equal "08125", Isbn.publisher_prefix("0812550102")
    assert_equal "0441", Isbn.publisher_prefix("0441576367")
    assert_nil Isbn.publisher_prefix("2070368228")
  end

  test "a UPC publisher can have several ISBN prefixes; a known one keeps to them, a new one is learnt alongside" do
    UpcPrefix.create!(manufacturer: "37145", known_prefixes: %w[0812 0765])
    middle("12345", pub("081212345"), pub("044112345"))
    assert_equal [ Isbn.to_13(isbn10("081212345")) ], UpcLookup.call(upc: "037145012346", add_on: "12345").isbns

    middle("54321", pub("076554321"), pub("055354321"))
    assert_equal [ Isbn.to_13(isbn10("076554321")) ], UpcLookup.call(upc: "037145099990", add_on: "54321").isbns

    middle("67890", pub("042567890"))           # a third Tor prefix, not known yet
    assert_equal %w[0425], UpcLookup.call(upc: "037145011111", add_on: "67890").prefixes
    assert_equal %w[0425 0765 0812], UpcPrefix.find_by!(manufacturer: "37145").known_prefixes
  end

  test "a fuller form of a known prefix is the same publisher: DAW's 0886 finds 0-88677 at once" do
    UpcPrefix.create!(manufacturer: "71125", known_prefixes: %w[0886])
    smugglers = pub("088677299")
    middle("00299", smugglers, pub("038000299"), pub("078600299"))

    assert_equal [ smugglers["isbn_13"] ], UpcLookup.call(upc: "071125003504", add_on: "00299").isbns
  end
end
