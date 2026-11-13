require "test_helper"

class ContributorPenNamesTest < ActiveSupport::TestCase
  test "a pen name's real author; other forms of the same name and non-Latin names apart" do
    webb = Contributor.create!(name: "Catherine Webb", external_ids: { "isfdb" => "77" })
    north = Contributor.create!(name: "Claire North", isfdb_names: { "pseudonyms" => [], "pseudonym_of" => [ { "id" => "77", "name" => "Catherine Webb" } ] })
    banks = Contributor.create!(name: "Iain Banks", isfdb_names: { "pseudonyms" => [], "pseudonym_of" => [ { "id" => "9", "name" => "Iain M. Banks" } ] })
    arkady = Contributor.create!(name: "Arkady Strugatsky",
                                 isfdb_names: { "pseudonyms" => [], "pseudonym_of" => [ { "id" => "5", "name" => "&#1040;&#1088;&#1082;&#1072;&#1076;&#1080;&#1081;" } ] })
    wyndham = Contributor.create!(name: "John Wyndham",
                                  isfdb_names: { "pseudonyms" => [ { "id" => "13832", "name" => "John Beynon Harris" }, { "id" => "1", "name" => "Lucas Parkes" } ], "pseudonym_of" => [] })

    assert_equal [ webb ], north.pen_name_of.map(&:contributor)
    assert_empty banks.pen_name_of
    assert_equal [ "Iain M. Banks" ], banks.published_as.map(&:name)
    assert_empty arkady.pen_name_of + arkady.published_as
    assert_equal [ "John Beynon Harris", "Lucas Parkes" ], wyndham.published_as.map(&:name)
  end
end
