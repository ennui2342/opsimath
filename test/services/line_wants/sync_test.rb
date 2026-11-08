require "test_helper"

module LineWants
  class SyncTest < ActiveSupport::TestCase
    setup do
      Rails.cache.clear
      @isfdb = ENV.fetch("ISFDB_ADAPTER_URL")
      # #2 is Mark's (that printing); #3 is a book he has in another edition; #1 isn't catalogued at all.
      @mine = book("The Female Man", pub_ids: %w[500], owned: true)
      @other = book("Native Tongue", pub_ids: %w[900], owned: true)
      stub_request(:get, "#{@isfdb}/pubseries/77").to_return(status: 200, body: {
        id: 77, name: "The Women's Press Science Fiction",
        publications: [ pub(499, "1", "Walk to the End of the World", 1001), pub(500, "2", "The Female Man", 1002),
                        pub(501, "3", "Native Tongue", 1003) ]
      }.to_json)
      WorkIdentifier.create!(work: @other, id_type: "isfdb_title", value: "1003")
      @line_want = LineWant.create!(pub_series_id: 77)
    end

    def pub(id, num, title, title_id) = { "_isfdb_pub_id" => id, "_isfdb_title_id" => title_id, "pub_series_num" => num, "title" => title,
                                          "authors" => [ "Suzy McKee Charnas" ], "publisher" => "The Women's Press", "publish_date" => "1985" }

    def book(title, pub_ids:, owned:)
      work = Work.create!(title:, literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      pub_ids.each { |id| edition.edition_identifiers.create!(id_type: "isfdb", value: id) }
      Copy.create!(edition:, disposition: "owned") if owned
      work
    end

    test "wants every number that isn't Mark's printing, in that printing; a missing book is added to the catalogue" do
      assert_equal 2, Sync.run(@line_want)

      walk = Work.find_by!(title: "Walk to the End of the World")
      assert_equal [ [ 499 ], @line_want.id ], [ walk.want.printing_override_ids, walk.want.line_want_id ]
      assert_equal [ 501 ], @other.reload.want.printing_override_ids # an upgrade: the line's printing
      assert_nil @mine.reload.want
      assert_equal 0, Sync.run(@line_want) # nothing new the second time
    end

    test "excluded numbers stay out; stopping removes only the wants the line made" do
      @line_want.update!(excluded_pub_ids: [ 501 ])
      own = Want.create!(work: Work.create!(title: "Walk to the End of the World", literary_form: "novel")) # Mark's own
      WorkIdentifier.create!(work: own.work, id_type: "isfdb_title", value: "1001")

      Sync.run(@line_want)
      assert_nil @other.reload.want
      assert_includes own.reload.printing_override_ids, 499

      @line_want.stop!
      assert Want.exists?(own.id)
    end

    test "nothing happens until the full line is available" do
      stub_request(:get, "#{@isfdb}/pubseries/77").to_return(status: 503, body: "{}")
      Rails.cache.clear

      assert_equal 0, Sync.run(@line_want)
      assert_equal 0, Want.count
    end
  end
end
