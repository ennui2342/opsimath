require "test_helper"

class EditionIdentifierTest < ActiveSupport::TestCase
  test "external_url links isfdb and goodreads ids to their canonical page" do
    isfdb = EditionIdentifier.new(id_type: "isfdb", value: "12345")
    goodreads = EditionIdentifier.new(id_type: "goodreads", value: "67890")

    assert_equal "https://www.isfdb.org/cgi-bin/pl.cgi?12345", isfdb.external_url
    assert_equal "https://www.goodreads.com/book/show/67890", goodreads.external_url
  end

  test "external_url is nil for id_types with no single canonical page" do
    isbn = EditionIdentifier.new(id_type: "isbn13", value: "9780000000000")

    assert_nil isbn.external_url
  end

  test "label uses the canonical display name, falling back to the upcased type" do
    assert_equal "ISBN-13", EditionIdentifier.new(id_type: "isbn13").label
    assert_equal "ISFDB", EditionIdentifier.new(id_type: "isfdb").label
    assert_equal "ASIN", EditionIdentifier.new(id_type: "asin").label
  end

  test "for_display orders ISBNs first, then linkable ids, then the rest" do
    ids = %w[goodreads asin isbn10 isfdb isbn13].map { |t| EditionIdentifier.new(id_type: t, value: "x") }

    assert_equal %w[isbn13 isbn10 isfdb goodreads asin], EditionIdentifier.for_display(ids).map(&:id_type)
  end
end
