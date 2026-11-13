require "test_helper"

module BookLists
  class ImportTest < ActiveSupport::TestCase
    ISFDB = ENV.fetch("ISFDB_ADAPTER_URL")

    test "an award category: every year's winner and shortlist, by main title; 'no award' left out" do
      stub_request(:get, "#{ISFDB}/awards/categories/7").to_return(status: 200, body: {
        id: "7", name: "Best Novel", award: { id: "3", name: "Arthur C. Clarke Award" },
        entries: [ { year: 2019, status: "winner", title: "Rosewater", author: "Tade Thompson", title_id: 10, main_title_id: 10 },
                   { year: 2019, status: "shortlisted", title: "Semiosis", author: "Sue Burke", title_id: 11, main_title_id: 9 },
                   { year: 1990, status: nil, title: "No Award", author: "", title_id: nil, main_title_id: nil } ]
      }.to_json)

      list = Import.new.award(7)

      assert_equal [ "Arthur C. Clarke Award: Best Novel", "Arthur C. Clarke", "award" ], [ list.name, list.short_name, list.kind ]
      assert_equal [ [ "Rosewater", "winner", 10 ], [ "Semiosis", "shortlisted", 9 ] ], list.entries.map { |e| [ e.title, e.status, e.isfdb_title_id ] }
    end

    test "a curated list: each entry matched to its ISFDB main title by title and surname; one that doesn't match stays unmatched" do
      stub_request(:get, %r{#{ISFDB}/search}).to_return do |req|
        q = URI.decode_www_form(URI(req.uri).query).to_h["q"]
        rows = q.start_with?("Earth Abides") ? [ { "_isfdb_title_id" => 55, "title" => "Earth Abides", "authors" => [ "George R. Stewart" ] } ] : []
        { status: 200, body: rows.to_json }
      end
      stub_request(:get, "#{ISFDB}/titles/55").to_return(status: 200, body: { id: 55, main: { id: 50, title: "Earth Abides" }, variants: [] }.to_json)
      data = { "key" => "pringle_100", "name" => "Pringle's 100", "short_name" => "Pringle 100",
               "entries" => [ { "title" => "Earth Abides", "author" => "George R. Stewart", "year" => 1949, "position" => 2 },
                              { "title" => "Limbo", "author" => "Bernard Wolfe", "year" => 1952, "position" => 6 } ] }

      list = Import.new.curated("pringle_100", data:)

      assert_equal [ [ "Earth Abides", 50, 2 ], [ "Limbo", nil, 6 ] ], list.entries.map { |e| [ e.title, e.isfdb_title_id, e.position ] }
      assert_equal %w[listed listed], list.entries.map(&:status)
    end

    test "the real curated lists load: Pringle's 100 and Broderick & Di Filippo's 102 books" do
      assert_equal %w[broderick_101 pringle_100], Import.curated_keys
      assert_equal 100, YAML.load_file(Import::CURATED_DIR.join("pringle_100.yml"))["entries"].size
      assert_equal 102, YAML.load_file(Import::CURATED_DIR.join("broderick_101.yml"))["entries"].size
    end
  test "several ISFDB titles of one name by one author: the one nearest the list's year" do
      stub_request(:get, %r{#{ISFDB}/search}).to_return(status: 200, body: [
        { "_isfdb_title_id" => 2835759, "title" => "The Martian Chronicles", "authors" => [ "Ray Bradbury" ] },
        { "_isfdb_title_id" => 21571, "title" => "The Martian Chronicles", "authors" => [ "Ray Bradbury" ] }
      ].to_json)
      stub_request(:get, "#{ISFDB}/titles/2835759").to_return(status: 200, body: { id: 2835759, main: { id: 2835759, year: 1997 }, variants: [] }.to_json)
      stub_request(:get, "#{ISFDB}/titles/21571").to_return(status: 200, body: { id: 21571, main: { id: 21571, year: 1950 }, variants: [] }.to_json)
      data = { "key" => "pringle_100", "name" => "P", "entries" => [ { "title" => "The Martian Chronicles", "author" => "Ray Bradbury", "year" => 1950 } ] }

      assert_equal 21571, Import.new.curated("pringle_100", data:).entries.sole.isfdb_title_id
    end
  end
end
