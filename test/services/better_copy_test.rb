require "test_helper"

class BetterCopyTest < ActiveSupport::TestCase
  setup do
    @work = Work.create!(title: "Beggars and Choosers", literary_form: "novel")
    @edition = Edition.create!(publisher: "Tor", publish_date: "1996")
    EditionContent.create!(work: @work, edition: @edition)
    Copy.create!(edition: @edition, disposition: "owned")
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "4242")
  end

  test "a book not wanted: onto the wishlist hunting exactly that printing" do
    want = BetterCopy.want(@work, @edition)

    assert_equal [ 4242 ], want.printing_override_ids
    assert_match "My Tor 1996 edition, in better condition", want.notes
    assert BetterCopy.wanted?(@work.reload, @edition)
    assert_equal "Beggars and Choosers: wanting the Tor 1996 edition in better condition", CatalogueEvent.last.summary
  end

  test "a book already wanted for chosen covers keeps them and gains the printing; asking twice changes nothing" do
    Want.create!(work: @work, printing_override_ids: [ 7 ])

    BetterCopy.want(@work, @edition)
    BetterCopy.want(@work.reload, @edition)

    assert_equal [ 7, 4242 ], @work.want.reload.printing_override_ids
    assert_equal 1, @work.want.notes.scan("in better condition").size
  end

  test "an edition not linked to its ISFDB printing is refused" do
    @edition.edition_identifiers.destroy_all

    assert_raises(BetterCopy::Refused) { BetterCopy.want(@work, @edition.reload) }
    assert_nil @work.reload.want
  end
end
