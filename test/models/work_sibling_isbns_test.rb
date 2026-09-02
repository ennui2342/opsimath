require "test_helper"

class WorkSiblingIsbnsTest < ActiveSupport::TestCase
  test "for_works returns only works that have a non-empty list" do
    WorkSiblingIsbns.create!(work_id: 1, isbn13s: %w[9780000000001 9780000000002], queried_isbns: %w[9780000000001], refreshed_at: Time.current)
    WorkSiblingIsbns.create!(work_id: 2, isbn13s: [], queried_isbns: %w[9780000000009], refreshed_at: Time.current)

    result = WorkSiblingIsbns.for_works([ 1, 2, 3 ])

    assert_equal({ 1 => %w[9780000000001 9780000000002] }, result)
  end

  test "stale? is true when older than max_age" do
    row = WorkSiblingIsbns.new(queried_isbns: %w[a b], refreshed_at: 10.days.ago)
    assert row.stale?(%w[a b], max_age: 7.days)

    row.refreshed_at = 2.days.ago
    assert_not row.stale?(%w[a b], max_age: 7.days)
  end

  test "stale? is true when the work's ISBNs have changed since it was queried" do
    row = WorkSiblingIsbns.new(queried_isbns: %w[a b], refreshed_at: 1.hour.ago)

    assert_not row.stale?(%w[b a], max_age: 7.days) # order-independent
    assert row.stale?(%w[a b c], max_age: 7.days)   # gained an ISBN
  end
end
