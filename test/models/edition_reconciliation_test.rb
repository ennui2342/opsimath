require "test_helper"

class EditionReconciliationTest < ActiveSupport::TestCase
  setup do
    @work = Work.create!(title: "Crossfire", literary_form: "novel")
    @ed1 = Edition.create!(format: "hardcover")
    @ed2 = Edition.create!(format: "paperback")
    EditionContent.create!(work: @work, edition: @ed1)
    EditionContent.create!(work: @work, edition: @ed2)
  end

  def build(**payload_overrides)
    EditionReconciliation.create!(
      work: @work,
      payload: {
        "goodreads_book_id" => "999",
        "shelf" => "read",
        "work_id" => @work.id,
        "candidate_edition_ids" => [ @ed1.id, @ed2.id ],
        "feed_item" => {
          "goodreads_book_id" => "999", "title" => "Crossfire", "author_name" => "Nancy Kress",
          "isbn" => "0812564022", "user_read_at" => "2024-01-05"
        }
      }.merge(payload_overrides)
    )
  end

  test "feed_item rebuilds the FeedItem struct from the payload" do
    item = build.feed_item

    assert_instance_of Goodreads::RssClient::FeedItem, item
    assert_equal "999", item.goodreads_book_id
    assert_equal "0812564022", item.isbn
    assert_equal "Crossfire", item.title
  end

  test "shelf / incoming_goodreads_id / incoming_isbn read from the payload" do
    rec = build
    assert_equal "read", rec.shelf
    assert_equal "999", rec.incoming_goodreads_id
    assert_equal "0812564022", rec.incoming_isbn
  end

  test "incoming_isbn is nil when the feed carried none" do
    rec = build("feed_item" => { "goodreads_book_id" => "999", "title" => "X" })
    assert_nil rec.incoming_isbn
  end

  test "candidate_editions returns the work's editions in id order" do
    assert_equal [ @ed1.id, @ed2.id ], build.candidate_editions.map(&:id)
  end

  test "comparison_cards: an incoming (proposed) card plus one selectable card per edition" do
    Copy.create!(edition: @ed1, disposition: "owned")
    Reading.create!(work: @work, edition: @ed1, status: "completed", source: "owned_copy")
    cards = build("feed_item" => {
      "goodreads_book_id" => "999", "title" => "Crossfire", "isbn" => "0812564022",
      "user_read_at" => "2024-01-05", "book_image_url" => "https://example.com/c.jpg"
    }).comparison_cards

    assert cards[:incoming].proposed
    assert_equal "https://example.com/c.jpg", cards[:incoming].cover_url
    assert_equal "0812564022", cards[:incoming].fields.find { |f| f.name == "isbn" }.value

    assert_equal 2, cards[:editions].size
    owned = cards[:editions].first
    assert_equal "Edition · owned · read", owned.label
    assert_equal "target_edition_id", owned.select_name
    assert_equal @ed1.id.to_s, owned.select_value
    assert owned.selected
    assert_equal "Edition · catalog", cards[:editions].last.label
    assert_not cards[:editions].last.selected
  end

  test "status and resolution enums" do
    rec = build
    assert rec.pending?

    rec.update!(status: "resolved", resolution: "change_edition", resolved_edition: @ed2, resolved_at: Time.current)
    assert rec.resolved?
    assert rec.resolution_change_edition?
    assert_equal @ed2, rec.resolved_edition
  end
end
