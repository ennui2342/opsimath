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

  test "backfill_isbn_pair! derives the missing half of the ISBN pair" do
    edition = Edition.create!
    edition.edition_identifiers.create!(id_type: "isbn10", value: "0441569595")

    edition.backfill_isbn_pair!

    assert_equal "9780441569595", edition.edition_identifiers.find_by(id_type: "isbn13").value
  end

  test "backfill_isbn_pair! is a no-op when both are present or neither is derivable" do
    both = Edition.create!
    both.edition_identifiers.create!(id_type: "isbn10", value: "0441569595")
    both.edition_identifiers.create!(id_type: "isbn13", value: "9999999999999")
    assert_no_difference -> { both.edition_identifiers.count } do
      both.backfill_isbn_pair!
    end

    none = Edition.create!
    none.edition_identifiers.create!(id_type: "goodreads", value: "123")
    assert_no_difference -> { none.edition_identifiers.count } do
      none.backfill_isbn_pair!
    end
  end
end
