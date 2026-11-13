require "test_helper"

module Isfdb
  class LinkReconcileTest < ActiveSupport::TestCase
    ISFDB = ENV.fetch("ISFDB_ADAPTER_URL")

    def title(id, main_id, name)
      stub_request(:get, "#{ISFDB}/titles/#{id}").to_return(status: 200, body: { id:, title: name, main: { id: main_id, title: name, type: "NOVEL" }, variants: [] }.to_json)
    end

    # A book with one edition anchored to `pub`, a printing of `own_title`.
    def book(name, links:, pub:, own_title:)
      work = Work.create!(title: name, literary_form: "novel")
      links.each { |l| work.work_identifiers.create!(id_type: "isfdb_title", value: l.to_s) }
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      edition.edition_identifiers.create!(id_type: "isfdb", value: pub.to_s)
      ProviderEdition.create!(work:, provider: "isfdb", provider_id: pub.to_s, title: name, provider_work_id: own_title&.to_s)
      work
    end

    test "an omnibus linked to a novel in it: the novel's link dropped and rejected, the omnibus's added, its title restored" do
      title(1911, 1911, "The Forever War")
      title(5000, 5000, "Peace and War")
      work = book("The Forever War", links: [ 1911 ], pub: 287484, own_title: 5000)
      work.update!(field_sources: { "title" => "isfdb" })
      work.work_alternate_titles.create!(title: "Peace and War", note: "its title before ISFDB's")

      change = LinkReconcile.plan.sole
      assert_equal [ [ "1911", "The Forever War" ] ], change.drop
      assert_equal [ [ "5000", "Peace and War" ] ], change.add
      assert_equal "Peace and War", change.restore_title

      LinkReconcile.apply
      work.reload
      assert_equal [ "5000" ], work.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
      assert work.work_identifiers.exists?(id_type: "isfdb_title_rejected", value: "1911")
      assert_equal "Peace and War", work.title
    end

    test "a variant of the same book is the same: no change; a book not yet refetched isn't judged" do
      title(7702, 7701, "Village of the Damned")
      title(7701, 7701, "The Midwich Cuckoos")
      book("The Midwich Cuckoos", links: [ 7701 ], pub: 1, own_title: 7702)
      book("Unfetched", links: [ 9 ], pub: 2, own_title: nil)

      r = LinkReconcile.new
      assert_empty r.plan
      assert_equal 1, r.skipped
    end

    test "an edition's title rejected before is a conflict for Mark, never re-added" do
      title(172997, 172997, "The Midwich Cuckoos")
      title(7701, 7701, "The Midwich Cuckoos")
      work = book("The Midwich Cuckoos", links: [ 7701 ], pub: 3, own_title: 172997)
      work.work_identifiers.create!(id_type: "isfdb_title_rejected", value: "172997")

      change = LinkReconcile.plan.sole
      assert_empty change.add
      assert_empty change.drop # the novel's link isn't touched on the strength of a doubtful anchor
      assert_equal [ "172997" ], change.conflicts.map(&:first)
    end
  end
end
