require "test_helper"

class MobileThumbTest < ActiveSupport::TestCase
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

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

  test "seed_from_snapshot repopulates the cache from the snapshot file's thumb BLOBs" do
    work = Work.create!(title: "Seeded", literary_form: "novel")
    edition = Edition.create!(format: "paperback")
    EditionContent.create!(work:, edition:)
    edition.cover_image.attach(io: StringIO.new(PNG), filename: "c.png", content_type: "image/png")
    Copy.create!(edition:, disposition: "owned")
    wishlist = WishlistItem.create!(title: "W", external_ids: { "isbn13" => "9780000000002" })
    wishlist.cover_image.attach(io: StringIO.new(PNG), filename: "w.png", content_type: "image/png")

    snapshot = MobileSnapshot.regenerate!(isfdb: nil) # build caches thumbs as it goes
    e_key = edition.cover_image.variant(:thumb).processed.key
    w_key = wishlist.cover_image.variant(:thumb).processed.key
    e_bytes = MobileThumb.find(e_key).data
    MobileThumb.delete_all

    seeded = MobileThumb.seed_from_snapshot(snapshot)

    assert_equal 2, seeded
    assert_equal e_bytes, MobileThumb.find(e_key).data
    assert_predicate MobileThumb.find(w_key).byte_size, :positive?
  end

  test "seed_from_snapshot is a no-op with no snapshot" do
    assert_equal 0, MobileThumb.seed_from_snapshot(nil)
  end
end
