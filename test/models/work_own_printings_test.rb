require "test_helper"

class WorkOwnPrintingsTest < ActiveSupport::TestCase
  test "a book's own ISFDB printings are those of its own title, not an omnibus's containing it" do
    work = Work.create!(title: "Wetware", literary_form: "novel")
    work.work_identifiers.create!(id_type: "isfdb_title", value: "868")
    own = ProviderEdition.create!(work:, provider: "isfdb", provider_id: "54237", title: "Wetware", provider_work_id: "868")
    ProviderEdition.create!(work:, provider: "isfdb", provider_id: "20507", title: "Live Robots", provider_work_id: "11111")
    unknown = ProviderEdition.create!(work:, provider: "isfdb", provider_id: "1", title: "Wetware") # stored before titles were kept

    assert_equal [ own, unknown ].map(&:id).sort, work.reload.own_isfdb_printings.map(&:id).sort
  end
end
