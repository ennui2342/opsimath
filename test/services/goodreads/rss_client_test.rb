require "test_helper"

module Goodreads
  class RssClientTest < ActiveSupport::TestCase
    def parse(name)
      client = RssClient.allocate
      body = File.read(Rails.root.join("test/fixtures/files/goodreads_#{name}_sample.xml"))
      client.send(:parse, body)
    end

    test "parses a real read-shelf item, including the reread signal" do
      items = parse("read")
      neuromancer = items.find { |i| i.goodreads_book_id == "953070" }

      assert_equal "Neuromancer (Sprawl #1)", neuromancer.title
      assert_equal "William Gibson", neuromancer.author_name
      assert_nil neuromancer.isbn # confirmed real gap — not every item has one
      assert_equal 317, neuromancer.num_pages
      assert_equal "1984", neuromancer.book_published
      assert_equal 5.0, neuromancer.user_rating
      assert_equal Date.new(2026, 7, 28), neuromancer.user_read_at
      assert_equal Date.new(2026, 8, 3), neuromancer.user_date_added
      assert_equal [ "sci-fi" ], neuromancer.user_shelves
      assert_match(/re-read was in order/, neuromancer.user_review)
    end

    test "parses comma-separated user_shelves" do
      items = parse("read")
      watson = items.find { |i| i.goodreads_book_id == "698910" }

      assert_equal [ "collection", "sci-fi" ], watson.user_shelves
    end

    test "parses a real to-read item with a real isbn" do
      items = parse("to_read")
      europe = items.find { |i| i.goodreads_book_id == "39666185" }

      assert_equal "1781086095", europe.isbn
      assert_equal "2018", europe.book_published
      assert_nil europe.user_read_at
    end

    test "parses a real currently-reading item (no isbn13 field exists at all)" do
      items = parse("currently_reading")
      clarkesworld = items.find { |i| i.goodreads_book_id == "256246282" }

      assert_equal "Clarkesworld Magazine, Issue 238, July 2026", clarkesworld.title
      assert_equal "1642362182", clarkesworld.isbn
      assert_equal Date.new(2026, 8, 4), clarkesworld.user_date_added
    end

    test "an unrated item's user_rating is nil, not 0" do
      items = parse("to_read")
      europe = items.find { |i| i.goodreads_book_id == "39666185" }

      assert_nil europe.user_rating
    end

    test "parses the single real did-not-finish item" do
      items = parse("did_not_finish")
      item = items.first

      assert_equal "17823844", item.goodreads_book_id
      assert_equal Date.new(2024, 5, 3), item.user_read_at
    end
  end
end
