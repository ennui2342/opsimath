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

    test "a book the line lists twice (two printings) is added once, wanting both printings" do
      stub_request(:get, "#{@isfdb}/pubseries/78").to_return(status: 200, body: {
        id: 78, name: "Ace Doubles", publications: [ pub(601, "1", "The Mind of Mr. Soames", 2001), pub(602, "9", "The Mind of Mr. Soames", 2001) ]
      }.to_json)

      Sync.run(LineWant.create!(pub_series_id: 78))

      soames = Work.where(title: "The Mind of Mr. Soames").sole
      assert_equal [ 601, 602 ], soames.want.printing_override_ids.sort
    end

    test "a book the line holds in two printings is one entry: having either is having it, and it's never wanted again" do
      stub_request(:get, "#{@isfdb}/pubseries/79").to_return(status: 200, body: {
        id: 79, name: "The Women's Press Science Fiction",
        publications: [ pub(55274, nil, "Woman on the Edge of Time", 4321).merge("publish_date" => "1987", "cover_url" => "https://c/sf.jpg"),
                        pub(1131336, nil, "Woman on the Edge of Time", 4321).merge("publish_date" => "1989") ]
      }.to_json)
      mine = book("Woman on the Edge of Time", pub_ids: %w[55274], owned: true)
      WorkIdentifier.create!(work: mine, id_type: "isfdb_title", value: "4321")

      line = PublicationLine.find(79)
      entry = line.entries.sole
      assert_equal [ :yours, [ 55274, 1131336 ] ], [ entry.status, entry.pub_ids ]
      assert_equal 0, Sync.run(LineWant.create!(pub_series_id: 79))
      assert_nil mine.reload.want
    end

    test "a book not yet had shows the printing with a cover; collecting wants any of its line printings" do
      stub_request(:get, "#{@isfdb}/pubseries/80").to_return(status: 200, body: {
        id: 80, name: "Line", publications: [ pub(2, nil, "Other Book", 77).merge("publish_date" => "1989"),
                                              pub(1, nil, "Other Book", 77).merge("publish_date" => "1987", "cover_url" => "https://c/x.jpg") ]
      }.to_json)

      entry = PublicationLine.find(80).entries.sole
      assert_equal 1, entry.pub_id # the one with a cover
      Sync.run(LineWant.create!(pub_series_id: 80))
      assert_equal [ 1, 2 ], Work.find_by!(title: "Other Book").want.printing_override_ids.sort
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
