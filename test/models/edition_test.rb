require "test_helper"

class EditionTest < ActiveSupport::TestCase
  # 1x1 PNG.
  PNG_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

  test "declares a :thumb cover variant that processes to WebP" do
    edition = Edition.create!
    edition.cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "cover.png", content_type: "image/png")

    processed = edition.cover_image.variant(:thumb).processed
    assert_equal "image/webp", processed.image.blob.content_type
  end
end
