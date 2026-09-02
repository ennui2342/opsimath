require "test_helper"

class MobileThumbTest < ActiveSupport::TestCase
  test "store inserts, then upserts the same key in place" do
    MobileThumb.store("variants/abc/def", "one")
    assert_equal 1, MobileThumb.count
    assert_equal({ "variants/abc/def" => "one" }, MobileThumb.fetch(%w[variants/abc/def]))

    MobileThumb.store("variants/abc/def", "two-longer")
    assert_equal 1, MobileThumb.count
    row = MobileThumb.find("variants/abc/def")
    assert_equal "two-longer", row.data
    assert_equal 10, row.byte_size
  end

  test "store is a no-op for a blank key" do
    assert_no_difference -> { MobileThumb.count } do
      MobileThumb.store(nil, "x")
      MobileThumb.store("", "x")
    end
  end

  test "fetch returns only the keys it has" do
    MobileThumb.store("k1", "a")
    MobileThumb.store("k2", "b")

    assert_equal({ "k1" => "a", "k2" => "b" }, MobileThumb.fetch(%w[k1 k2 k3]))
    assert_empty MobileThumb.fetch([])
  end
end
