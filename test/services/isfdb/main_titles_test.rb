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
  end
end
