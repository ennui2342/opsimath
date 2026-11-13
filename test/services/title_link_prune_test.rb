require "test_helper"

class TitleLinkPruneTest < ActiveSupport::TestCase
  def title(id, main_id, name, type)
    stub_request(:get, "#{ENV.fetch("ISFDB_ADAPTER_URL")}/titles/#{id}").to_return(status: 200, body: {
      id:, title: name, type:, variants: [], main: { id: main_id, title: name, type: }
    }.to_json)
  end

  test "drops a link to a different work, keeps a variant of the kept title, and remembers the drop" do
    work = Work.create!(title: "The Midwich Cuckoos", literary_form: "novel")
    %w[172997 7701 7702].each { |v| work.work_identifiers.create!(id_type: "isfdb_title", value: v) }
    title(172997, 172997, "The Midwich Cuckoos", "CHAPBOOK")
    title(7701, 7701, "The Midwich Cuckoos", "NOVEL")
    title(7702, 7701, "Village of the Damned", "NOVEL")

    assert_equal [ "172997" ], TitleLinkPrune.plan.sole.drop.map(&:first)
    assert_equal 1, TitleLinkPrune.apply

    assert_equal %w[7701 7702], work.work_identifiers.where(id_type: "isfdb_title").pluck(:value).sort
    assert work.work_identifiers.exists?(id_type: "isfdb_title_rejected", value: "172997")
  end

  test "a book on a suspect link is left alone" do
    work = Work.create!(title: "The Lord of the Rings", literary_form: "novel", isfdb_main_title: "The Fellowship of the Ring")
    %w[1 2].each { |v| work.work_identifiers.create!(id_type: "isfdb_title", value: v) }
    title(1, 1, "The Fellowship of the Ring", "NOVEL")
    title(2, 2, "The Two Towers", "NOVEL")

    assert_empty TitleLinkPrune.plan
  end
end
