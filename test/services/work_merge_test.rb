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

    WorkMerge.merge!(keep:, drop:)

    want = keep.reload.want
    assert_equal [ 601, 602 ], want.printing_override_ids.sort
    assert_equal 500, want.target_price
    assert_equal 1, Want.where(work: keep).count
  end

  test "a wanted duplicate's want moves to an owned book that had none" do
    keep = book("Native Tongue")
    drop = book("Native Tongue", edition: false)
    drop.create_want!

    WorkMerge.merge!(keep:, drop:)

    assert keep.reload.want
  end
end
