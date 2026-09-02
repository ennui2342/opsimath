require "test_helper"

module Goodreads
  class EditionBuilderTest < ActiveSupport::TestCase
    setup do
      @work = Work.create!(title: "Crossfire", literary_form: "novel")
    end

    def item(**overrides)
      RssClient::FeedItem.new(
        goodreads_book_id: "8299", title: "Crossfire", author_name: "Nancy Kress",
        isbn: "0812564022", book_image_url: nil, **overrides
      )
    end

    test "creates an Edition linked to the work with goodreads + isbn identifiers and the derived isbn13" do
      edition = EditionBuilder.build(work: @work, item: item)

      assert_includes @work.reload.editions, edition
      ids = edition.edition_identifiers.pluck(:id_type, :value).to_h
      assert_equal "8299", ids["goodreads"]
      assert_equal "0812564022", ids["isbn10"]
      assert_equal Isbn.to_13("0812564022"), ids["isbn13"] # backfill_isbn_pair!
    end

    test "records a goodreads EnrichmentRecord for the cover" do
      stub_request(:get, "https://example.test/c.jpg")
        .to_return(status: 200, body: "jpeg-bytes", headers: { "Content-Type" => "image/jpeg" })

      edition = EditionBuilder.build(work: @work, item: item(book_image_url: "https://example.test/c.jpg"))

      assert edition.enrichment_records.exists?(provider: "goodreads", external_id: "8299")
    end

    test "does not create a Copy — ownership is the caller's decision" do
      edition = EditionBuilder.build(work: @work, item: item)
      assert_empty edition.copies
    end

    test "handles a feed item with no isbn" do
      edition = EditionBuilder.build(work: @work, item: item(isbn: nil))
      assert_equal %w[goodreads], edition.edition_identifiers.pluck(:id_type)
    end
  end
end
