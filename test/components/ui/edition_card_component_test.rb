require "test_helper"

module Ui
  class EditionCardComponentTest < ViewComponent::TestCase
    PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    test "headline joins publisher, year (from the EDTF date) and page count, dropping blanks" do
      edition = Edition.new(publisher: "Gollancz", publish_date: "1987-05", page_count: 471)
      assert_equal "Gollancz · 1987 · 471 pages", card(edition).headline

      assert_equal "Orbit", card(Edition.new(publisher: "Orbit")).headline
    end

    test "headline falls back to format_line when there's no publisher/date/pages at all" do
      assert_equal "Hardcover", card(Edition.new(format: "hardcover")).headline
      assert_equal "Edition", card(Edition.new).headline
    end

    test "format line prefers format_detail, then format, then a generic fallback" do
      assert_equal "Mass market", card(Edition.new(format_detail: "mass_market", format: "paperback")).format_line
      assert_equal "Hardcover", card(Edition.new(format: "hardcover")).format_line
      assert_equal "Edition", card(Edition.new).format_line
    end

    test "detail_line is format plus the ISFDB cover artist, dropping either when blank" do
      assert_equal "Mass market · Bruce Pennington", card(Edition.new(format_detail: "mass_market", cover_artist: "Bruce Pennington")).detail_line
      assert_equal "Hardcover", card(Edition.new(format: "hardcover")).detail_line
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

    test "ownership_badge reads Owned for an owned copy, the disposition otherwise, nothing for a catalogue-only edition" do
      owned = Edition.create!
      Copy.create!(edition: owned, disposition: "owned")
      assert_equal [ "Owned", :success ], card(owned).ownership_badge

      replaced = Edition.create!
      Copy.create!(edition: replaced, disposition: "replaced")
      assert_equal [ "Replaced", :default ], card(replaced).ownership_badge

      assert_nil card(Edition.create!).ownership_badge
    end

    test "an owned copy wins the ownership badge over a retired one on the same edition" do
      edition = Edition.create!
      Copy.create!(edition:, disposition: "replaced")
      Copy.create!(edition:, disposition: "owned")

      assert_equal [ "Owned", :success ], card(edition).ownership_badge
    end

    test "reading_badge: open (or paused) beats completed beats dnf, and TBR when there's a copy/reading but no completed status" do
      work = Work.create!(title: "T", literary_form: "novel")

      owned_unread = Edition.create!
      Copy.create!(edition: owned_unread, disposition: "owned")
      assert_equal [ "TBR", :default ], card(owned_unread).reading_badge

      mid_reread = Edition.create!
      EditionContent.create!(work:, edition: mid_reread)
      Copy.create!(edition: mid_reread, disposition: "owned")
      Reading.create!(work:, edition: mid_reread, status: "completed", source: "owned_copy")
      Reading.create!(work:, edition: mid_reread, status: "reading", source: "owned_copy")
      assert_equal [ "Reading", :accent ], card(mid_reread).reading_badge

      finished = Edition.create!
      EditionContent.create!(work:, edition: finished)
      Copy.create!(edition: finished, disposition: "owned")
      Reading.create!(work:, edition: finished, status: "completed", source: "owned_copy")
      assert_equal [ "Read", :info ], card(finished).reading_badge

      abandoned = Edition.create!
      EditionContent.create!(work:, edition: abandoned)
      Copy.create!(edition: abandoned, disposition: "owned")
      Reading.create!(work:, edition: abandoned, status: "dnf", source: "owned_copy")
      assert_equal [ "DNF", :default ], card(abandoned).reading_badge
    end

    test "reading_badge shows on an unowned library read, and is nil for a catalogue-only edition with no copy and no reading" do
      work = Work.create!(title: "T", literary_form: "novel")
      library_read = Edition.create!
      EditionContent.create!(work:, edition: library_read)
      Reading.create!(work:, edition: library_read, status: "completed", source: "library")

      assert_equal [ "Read", :info ], card(library_read).reading_badge
      assert_nil card(library_read).ownership_badge # no copy — not "mine" in the ownership sense

      assert_nil card(Edition.create!).reading_badge # nothing to say about a bare alternate
    end

    test "status_badges combines ownership and reading, in that order, skipping whichever is nil" do
      work = Work.create!(title: "T", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      Copy.create!(edition:, disposition: "owned")
      Reading.create!(work:, edition:, status: "completed", source: "owned_copy")

      assert_equal [ [ "Owned", :success ], [ "Read", :info ] ], card(edition).status_badges
      assert_equal [], card(Edition.create!).status_badges
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

      assert_no_selector "[data-cover-picker-target='panel']"
      assert_no_selector "[data-action*='cover-picker']"
    end

    test "right-click cover picker rolls out a panel in place (not a <dialog>), one large cover per source" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(PNG), filename: "current.png", content_type: "image/png")
      isfdb = EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: {})
      isfdb.cover_image.attach(io: StringIO.new(PNG), filename: "isfdb.png", content_type: "image/png")

      render_inline(EditionCardComponent.new(edition: edition.reload))

      assert_no_selector "dialog" # not a native dialog — starts hidden, positioned relative to the cover
      assert_selector "img[data-action='contextmenu->cover-picker#open']"
      assert_selector "[data-cover-picker-target='panel'][hidden].absolute", visible: false
      assert_selector "[data-cover-picker-target='panel'] form[action='#{Rails.application.routes.url_helpers.edition_metadata_path(edition)}'] input[value='isfdb:cover_image']", visible: false
      assert_text "Isfdb"
    end

    private

    def card(edition) = EditionCardComponent.new(edition:)
  end
end
