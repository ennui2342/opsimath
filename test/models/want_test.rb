require "test_helper"

class WantTest < ActiveSupport::TestCase
  test "add! creates the work, its author and the want, ISBNs folded to 13" do
    want = Want.add!(title: "Vagabonds", author_name: "Hao Jingfang", isbns: [ "1534422080", "" ], external_ids: { "goodreads" => "1" })

    assert_equal [ "Vagabonds", "Hao Jingfang", [ Isbn.to_13("1534422080") ] ], [ want.title, want.author_name, want.seed_isbns ]
    assert_equal "goodreads", want.work.field_sources["title"]
  end

  test "add! reuses an author already in the catalogue" do
    existing = Contributor.create!(name: "Tanith Lee")

    assert_equal existing, Want.add!(title: "The Birthgrave", author_name: "tanith lee").author
  end

  test "retire! keeps a work that's catalogued otherwise, drops an empty placeholder" do
    wanted_only = create_want(title: "A")
    owned = create_want(title: "B")
    edition = Edition.create!
    EditionContent.create!(work: owned.work, edition:)

    wanted_only.retire!
    owned.retire!

    assert_not Work.exists?(wanted_only.work_id)
    assert Work.exists?(owned.work_id)
  end
end
