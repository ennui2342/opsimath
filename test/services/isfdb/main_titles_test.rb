require "test_helper"

module Isfdb
  class MainTitlesTest < ActiveSupport::TestCase
    test "a book's ISFDB main title and variants, from its isfdb_title link" do
      work = Work.create!(title: "Voyage to Venus", literary_form: "novel")
      work.work_identifiers.create!(id_type: "isfdb_title", value: "5501")
      stub_request(:get, "#{ENV.fetch("ISFDB_ADAPTER_URL")}/titles/5501").to_return(status: 200, body: {
        id: 5501, title: "Voyage to Venus", main: { id: 1300, title: "Perelandra" },
        variants: [ { id: 5501, title: "Voyage to Venus", language: "eng" }, { id: 77, title: "Perelandra (Voyage to Venus)", language: "eng" } ]
      }.to_json)

      assert_equal 1, MainTitles.run

      work.reload
      assert_equal "Perelandra", work.isfdb_main_title
      assert_equal [ "Voyage to Venus", "Perelandra (Voyage to Venus)" ], work.isfdb_variant_titles
      assert_equal 0, MainTitles.run # fresh: not fetched again
    end
  test "a translation's main title is the original's: the book keeps its English title, entities decoded" do
      records = [ { "main" => { "id" => 1, "title" => "&#1055;&#1080;&#1082;&#1085;&#1080;&#1082;", "language" => "rus" },
                    "variants" => [ { "id" => 2, "title" => "Roadside Picnic", "language" => "eng" },
                                    { "id" => 3, "title" => "Picnic au bord du chemin", "language" => "fre" } ] } ]

      main, variants = MainTitles.english_titles(records, current: "Roadside Picnic")

      assert_equal "Roadside Picnic", main
      assert_equal [ "Пикник" ], variants
    end
  test "the book's form, first-publication year and language come from the main title, except a field Mark set" do
      work = Work.create!(title: "The Midwich Cuckoos", literary_form: "novel", original_publication_year: 1990,
                          field_sources: { "original_language" => "manual" }, original_language: "en")
      work.work_identifiers.create!(id_type: "isfdb_title", value: "172997")
      stub_request(:get, "#{ENV.fetch("ISFDB_ADAPTER_URL")}/titles/172997").to_return(status: 200, body: {
        id: 172997, title: "The Midwich Cuckoos", type: "CHAPBOOK",
        main: { id: 172997, title: "The Midwich Cuckoos", type: "CHAPBOOK", year: 1957, language: "eng" }, variants: []
      }.to_json)

      MainTitles.run

      work.reload
      assert_equal [ "novella", 1957, "en" ], [ work.literary_form, work.original_publication_year, work.original_language ]
      assert_equal "isfdb", work.field_sources["literary_form"]
    end
  test "a book linked to a record that shares nothing with it takes no form or year from it" do
      work = Work.create!(title: "The Adventures of Alyx", literary_form: "collection", isfdb_main_title: "Picnic on Paradise")

      assert_empty MainTitles.apply_book_fields(work, { "type" => "NOVEL", "year" => 1968, "language" => "eng" })
      assert_equal "collection", work.reload.literary_form
    end
  test "several title links: the one that is this book — matching title, a real book over a chapbook, the container over its contents" do
      rec = ->(title, type, year) { { "title" => title, "main" => { "title" => title, "type" => type, "year" => year }, "variants" => [] } }
      chapbook = rec.("The Midwich Cuckoos", "CHAPBOOK", 2005)
      novel = rec.("The Midwich Cuckoos", "NOVEL", 1957)
      assert_equal novel, MainTitles.ordered([ chapbook, novel ], "The Midwich Cuckoos").first

      novella = rec.("\"If This Goes on—\"", "NOVEL", 1940)
      collection = rec.("Revolt in 2100", "COLLECTION", 1953)
      assert_equal collection, MainTitles.ordered([ novella, collection ], "Revolt in 2100").first

      both = [ rec.("Rainbow Mars", "NOVEL", 1999), rec.("Rainbow Mars", "COLLECTION", 1999) ]
      assert_equal "COLLECTION", MainTitles.ordered(both, "Rainbow Mars").first["main"]["type"]
    end
  end
end
