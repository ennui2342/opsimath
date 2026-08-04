require "test_helper"

module Goodreads
  class RowParserTest < ActiveSupport::TestCase
    test "clean_isbn strips Goodreads' Excel formula escape" do
      assert_equal "0425038521", RowParser.clean_isbn('="0425038521"')
      assert_nil RowParser.clean_isbn('=""')
      assert_nil RowParser.clean_isbn("")
    end

    test "clean_name collapses real doubled/tripled internal whitespace" do
      assert_equal "Keith Roberts", RowParser.clean_name("Keith       Roberts")
      assert_equal "Michael Bishop", RowParser.clean_name("Michael  Bishop")
      assert_nil RowParser.clean_name("  ")
    end

    test "additional_authors splits the real comma-separated column" do
      assert_equal [ "Kathryn Cramer", "David Langford" ],
        RowParser.additional_authors("Kathryn Cramer, David Langford")
    end

    test "rating treats 0 as unrated, not zero-star, per real data" do
      assert_nil RowParser.rating("0")
      assert_nil RowParser.rating("")
      assert_equal 5.0, RowParser.rating("5.0")
      assert_equal 3.0, RowParser.rating("3.0")
    end

    test "format_and_detail maps real Binding values" do
      assert_equal [ "paperback", nil ], RowParser.format_and_detail("Paperback")
      assert_equal [ "paperback", "mass_market" ], RowParser.format_and_detail("Mass Market Paperback")
      assert_equal [ "hardcover", nil ], RowParser.format_and_detail("Hardcover")
      assert_equal [ "ebook", nil ], RowParser.format_and_detail("Kindle Edition")
      assert_equal [ "audiobook", nil ], RowParser.format_and_detail("Audio CD")
    end

    test "format_and_detail falls back to paperback for unknown/blank binding" do
      assert_equal [ "paperback", nil ], RowParser.format_and_detail("Unknown Binding")
      assert_equal [ "paperback", nil ], RowParser.format_and_detail("")
    end

    test "read_events parses a real two-pair read_dates string (Echopraxia)" do
      events = RowParser.read_events("2016-01-30,2016-03-27;2024-10-05,2024-10-15", "2024/10/15")
      assert_equal 2, events.size
      assert_equal Date.new(2016, 1, 30), events[0].date_started
      assert_equal Date.new(2016, 3, 27), events[0].date_finished
      assert_equal Date.new(2024, 10, 5), events[1].date_started
      assert_equal Date.new(2024, 10, 15), events[1].date_finished
    end

    test "read_events falls back to Date Read (a different format) when read_dates is blank" do
      events = RowParser.read_events("", "2014/09/22")
      assert_equal 1, events.size
      assert_nil events[0].date_started
      assert_equal Date.new(2014, 9, 22), events[0].date_finished
    end

    test "read_events yields one event with nil dates when both columns are blank — not a flagged gap" do
      events = RowParser.read_events("", "")
      assert_equal 1, events.size
      assert_nil events[0].date_started
      assert_nil events[0].date_finished
    end

    test "series_info parses a real series-suffixed title" do
      info = RowParser.series_info("Marrow (Great Ship, #1)")
      assert_equal "Marrow", info.title
      assert_equal "Great Ship", info.series_name
      assert_equal 1.0, info.position
    end

    test "series_info parses a real title with no comma before the position" do
      info = RowParser.series_info("The Stone Canal (The Fall Revolution #2)")
      assert_equal "The Stone Canal", info.title
      assert_equal "The Fall Revolution", info.series_name
      assert_equal 2.0, info.position
    end

    test "series_info discards trailing text after the position (real A Song of Ice and Fire row)" do
      info = RowParser.series_info("A Dance with Dragons 1: Dreams and Dust (A Song of Ice and Fire, #5, Part 1 of 2)")
      assert_equal "A Dance with Dragons 1: Dreams and Dust", info.title
      assert_equal "A Song of Ice and Fire", info.series_name
      assert_equal 5.0, info.position
    end

    test "series_info leaves a genuinely parenthetical title (no #) alone" do
      info = RowParser.series_info("Simulacron 3 (IMAGINAIRE)")
      assert_equal "Simulacron 3 (IMAGINAIRE)", info.title
      assert_nil info.series_name
      assert_nil info.position
    end

    test "series_info leaves a plain title with no parens alone" do
      info = RowParser.series_info("Vast")
      assert_equal "Vast", info.title
      assert_nil info.series_name
    end

    test "extra_shelves drops the status shelves and keeps real genre/tag-ish labels" do
      assert_equal [ "essays", "sci-fi" ], RowParser.extra_shelves("essays, sci-fi")
      assert_equal [ "philosophy" ], RowParser.extra_shelves("philosophy, did-not-finish")
    end

    test "genre_lookup_name bridges Goodreads' informal 'sci-fi' to Thema's official 'Science fiction'" do
      assert_equal "Science fiction", RowParser.genre_lookup_name("sci-fi")
      assert_equal "Science fiction", RowParser.genre_lookup_name("SF")
    end

    test "genre_lookup_name passes an already-matching label through unchanged" do
      assert_equal "fantasy", RowParser.genre_lookup_name("fantasy")
      assert_equal "philosophy", RowParser.genre_lookup_name("philosophy")
    end

    test "work_type_from_shelves recognizes the real structural shelf labels" do
      assert_equal "anthology", RowParser.work_type_from_shelves("anthology, sci-fi")
      assert_equal "collection", RowParser.work_type_from_shelves("sci-fi, collection")
      assert_equal "essay", RowParser.work_type_from_shelves("essays, sci-fi")
    end

    test "work_type_from_shelves returns nil for subject-area labels — deliberately not inferring nonfiction" do
      assert_nil RowParser.work_type_from_shelves("philosophy, sci-fi")
      assert_nil RowParser.work_type_from_shelves("biography")
      assert_nil RowParser.work_type_from_shelves("ai")
    end
  end
end
