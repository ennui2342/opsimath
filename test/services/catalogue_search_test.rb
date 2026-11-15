require "test_helper"

class CatalogueSearchTest < ActiveSupport::TestCase
  test "numbers as digits, words or Roman numerals are the same; apostrophes don't matter" do
    two = Work.create!(title: "Best SF Two", literary_form: "anthology")
    visions = Work.create!(title: "Dangerous Visions II", literary_form: "anthology")
    years = Work.create!(title: "The Year's Best Science Fiction No. 1", literary_form: "anthology")
    works = [ two, visions, years ]

    assert_equal [ two ], CatalogueSearch.filter(works, "best sf 2")
    assert_equal [ visions ], CatalogueSearch.filter(works, "dangerous visions 2")
    assert_equal [ years ], CatalogueSearch.filter(works, "years best one")
  end
end
