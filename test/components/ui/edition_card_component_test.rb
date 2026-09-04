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

    test "identifier footer splits into an ISBN row and a linkable-id row" do
      edition = Edition.create!
      EditionIdentifier.create!(edition:, id_type: "isbn13", value: "9780575077255")
      EditionIdentifier.create!(edition:, id_type: "isbn10", value: "0575077255")
      EditionIdentifier.create!(edition:, id_type: "goodreads", value: "678")

      render_inline(EditionCardComponent.new(edition:))

      rows = page.all("div.font-mono > div")
      assert_equal 2, rows.size
      assert_equal %w[ISBN-13 ISBN-10], rows[0].all("b").map(&:text)
      assert_equal %w[Goodreads], rows[1].all("b").map(&:text)
    end

    test "status badge reads Owned for an owned copy, the disposition otherwise, nothing for a catalogue-only edition" do
      owned = Edition.create!
      Copy.create!(edition: owned, disposition: "owned")
      assert_equal [ "Owned", :success ], EditionCardComponent.new(edition: owned).status_badge

      replaced = Edition.create!
      Copy.create!(edition: replaced, disposition: "replaced")
      assert_equal [ "Replaced", :default ], EditionCardComponent.new(edition: replaced).status_badge

      assert_nil EditionCardComponent.new(edition: Edition.create!).status_badge
    end

    test "an owned copy wins the badge over a retired one on the same edition" do
      edition = Edition.create!
      Copy.create!(edition:, disposition: "replaced")
      Copy.create!(edition:, disposition: "owned")

      assert_equal [ "Owned", :success ], EditionCardComponent.new(edition:).status_badge
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

    test "links to the reconcile-metadata page via a cog in the corner" do
      edition = Edition.create!

      render_inline(EditionCardComponent.new(edition:))

      assert_selector "a[href='#{Rails.application.routes.url_helpers.edition_metadata_path(edition)}']"
    end

    test "cover_choices lists every source with an attached cover, nothing else" do
      edition = Edition.create!
      assert_empty EditionCardComponent.new(edition:).cover_choices

      goodreads = EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: {})
      EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "2", fetched_at: Time.current, raw_payload: {}, fields: {}) # no cover
      goodreads.cover_image.attach(io: StringIO.new(PNG), filename: "c.png", content_type: "image/png")

      assert_equal [ goodreads ], EditionCardComponent.new(edition: edition.reload).cover_choices
    end

    test "no right-click cover picker is wired when no source has a cover on file" do
      edition = Edition.create!

      render_inline(EditionCardComponent.new(edition:))

      assert_no_selector "dialog"
      assert_no_selector "[data-action*='cover-picker']"
    end

    test "right-click cover picker lists a card per source cover, posting to edition_metadata" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(PNG), filename: "current.png", content_type: "image/png")
      isfdb = EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: {})
      isfdb.cover_image.attach(io: StringIO.new(PNG), filename: "isfdb.png", content_type: "image/png")

      render_inline(EditionCardComponent.new(edition: edition.reload))

      assert_selector "img[data-action='contextmenu->cover-picker#open']"
      assert_selector "dialog[data-cover-picker-target='dialog']"
      assert_selector "dialog form[action='#{Rails.application.routes.url_helpers.edition_metadata_path(edition)}'] input[value='isfdb:cover_image']", visible: false
      assert_text "Isfdb"
    end

    private

    def card(edition) = EditionCardComponent.new(edition:)
  end
end
