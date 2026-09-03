require "test_helper"

module Ui
  class EditionCardComponentTest < ViewComponent::TestCase
    PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    test "format line prefers format_detail, then format, then a generic fallback" do
      assert_equal "Mass market", card(Edition.new(format_detail: "mass_market", format: "paperback")).format_line
      assert_equal "Hardcover", card(Edition.new(format: "hardcover")).format_line
      assert_equal "Edition", card(Edition.new).format_line
    end

    test "meta line joins publisher, year (from the EDTF date) and page count, dropping blanks" do
      edition = Edition.new(publisher: "Gollancz", publish_date: "1987-05", page_count: 471)
      assert_equal "Gollancz · 1987 · 471 pages", card(edition).meta_line

      assert_equal "Orbit", card(Edition.new(publisher: "Orbit")).meta_line
    end

    test "renders the identifier footer in canonical order, linking only ISFDB and Goodreads" do
      edition = Edition.create!(format: "paperback")
      EditionIdentifier.create!(edition:, id_type: "goodreads", value: "678")
      EditionIdentifier.create!(edition:, id_type: "isbn13", value: "9780575077255")
      EditionIdentifier.create!(edition:, id_type: "isfdb", value: "12345")

      render_inline(EditionCardComponent.new(edition:))

      labels = page.all(".font-mono span b").map(&:text)
      assert_equal %w[ISBN-13 ISFDB Goodreads], labels

      assert_selector "a[href='https://www.isfdb.org/cgi-bin/pl.cgi?12345']", text: "12345"
      assert_selector "a[href='https://www.goodreads.com/book/show/678']", text: "678"
      assert_no_selector "a", text: "9780575077255"
    end

    test "shows a dashed placeholder when no cover is attached" do
      render_inline(EditionCardComponent.new(edition: Edition.create!))

      assert_no_selector "img"
      assert_text "No cover"
    end

    test "renders the cover thumbnail when one is attached" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(PNG), filename: "c.png", content_type: "image/png")

      render_inline(EditionCardComponent.new(edition:))

      assert_selector "img"
      assert_no_text "No cover"
    end

    private

    def card(edition) = EditionCardComponent.new(edition:)
  end
end
