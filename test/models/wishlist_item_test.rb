require "test_helper"

class WishlistItemTest < ActiveSupport::TestCase
  test "has the shared :thumb cover variant" do
    item = WishlistItem.create!(title: "Vagabonds")
    item.cover_image.attach(io: StringIO.new(EditionTest::PNG_BYTES), filename: "c.png", content_type: "image/png")

    assert_equal "image/webp", item.cover_image.variant(:thumb).processed.image.blob.content_type
  end
end
