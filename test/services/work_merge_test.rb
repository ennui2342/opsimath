require "test_helper"

class WorkMergeTest < ActiveSupport::TestCase
  def book(title, edition: true)
    work = Work.create!(title:, literary_form: "novel")
    work.work_identifiers.create!(id_type: "isfdb_title", value: "1911")
    work.work_contributors.create!(contributor: (Contributor.find_by(name: "Joe Haldeman") || Contributor.create!(name: "Joe Haldeman")), role: "author", display_order: 0)
    if edition
      e = Edition.create!
      EditionContent.create!(work:, edition: e)
    end
    work
  end

  test "editions, readings and series move; shared credits and identifiers aren't doubled; the duplicate goes" do
    keep = book("The Forever War")
    drop = book("The Forever War")
    drop.update!(original_publication_year: 1974)
    reading = drop.readings.create!(edition: drop.editions.first, status: "completed", date_started: Date.new(2020, 1, 1), date_finished: Date.new(2020, 2, 1))
    series = Series.create!(name: "The Forever War")
    WorkSeries.create!(work: drop, series:, position: 1)

    WorkMerge.merge!(keep:, drop:)

    keep.reload
    assert_not Work.exists?(drop.id)
    assert_equal 2, keep.editions.count
    assert_equal keep, reading.reload.work
    assert_equal [ series ], keep.series.to_a
    assert_equal 1, keep.work_contributors.count
    assert_equal 1, keep.work_identifiers.count
    assert_equal 1974, keep.original_publication_year
  end

  test "two wants become one, hunting both's printings" do
    keep = book("The Mind of Mr. Soames", edition: false)
    drop = book("The Mind of Mr. Soames", edition: false)
    keep.create_want!(printing_override_ids: [ 601 ])
    drop.create_want!(printing_override_ids: [ 602 ], target_price: 500)
    [ keep, drop ].each { |w| EbayListing.create!(work: w, ebay_item_id: "v1|1|0", title: "Soames", found_by: "title", first_seen_at: Time.current, last_seen_at: Time.current) }

    WorkMerge.merge!(keep:, drop:)

    want = keep.reload.want
    assert_equal [ 601, 602 ], want.printing_override_ids.sort
    assert_equal 500, want.target_price
    assert_equal 1, Want.where(work: keep).count
    assert_equal 1, keep.ebay_listings.count # both had found the same listing
  end

  test "a wanted duplicate's want moves to an owned book that had none" do
    keep = book("Native Tongue")
    drop = book("Native Tongue", edition: false)
    drop.create_want!

    WorkMerge.merge!(keep:, drop:)

    assert keep.reload.want
  end

  test "two books whose editions are printings of different ISFDB titles aren't merged" do
    keep = book("The Forever War")
    drop = book("The Forever War")
    [ [ keep, "468971", "1911" ], [ drop, "287484", "5000" ] ].each do |w, pub, title_id|
      w.editions.first.edition_identifiers.create!(id_type: "isfdb", value: pub)
      ProviderEdition.create!(work: w, provider: "isfdb", provider_id: pub, provider_work_id: title_id)
    end

    assert_raises(WorkMerge::Different) { WorkMerge.merge!(keep:, drop:) }
    assert Work.exists?(drop.id)
  end
end
