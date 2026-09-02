require "test_helper"

class MobileSnapshotTest < ActiveSupport::TestCase
  setup do
    work = Work.create!(title: "Neuromancer", literary_form: "novel")
    edition = Edition.create!
    EditionContent.create!(work:, edition:)
    Copy.create!(edition:, disposition: "owned")
  end

  test "regenerate! creates the row, attaches the file, starts at version 1" do
    snapshot = MobileSnapshot.regenerate!

    assert_equal 1, snapshot.version
    assert snapshot.file.attached?
    assert snapshot.byte_size.positive?
    assert_equal 1, snapshot.entry_count
    assert_equal snapshot, MobileSnapshot.current
    assert_equal 1, MobileSnapshot.count
  end

  test "regenerate! bumps the version and replaces the file in place" do
    first = MobileSnapshot.regenerate!
    first_blob_id = first.file.blob.id

    second = MobileSnapshot.regenerate!

    assert_equal first, second
    assert_equal 2, second.reload.version
    assert_equal 1, MobileSnapshot.count
    assert_not_equal first_blob_id, second.file.blob.id # file replaced, not appended
  end
end
