require "test_helper"

class WorkRemovalTest < ActiveSupport::TestCase
  setup do
    author = Contributor.create!(name: "Clive Barker")
    @dupe = book("Books of Blood Volume 1", author)
    @kept = book("Books of Blood Volume One", author)
  end

  def book(title, author)
    work = Work.create!(title:, literary_form: "collection")
    work.work_contributors.create!(contributor: author, role: "author")
    edition = Edition.create!(publisher: "Sphere")
    EditionContent.create!(work:, edition:)
    Copy.create!(edition:, disposition: "owned")
    work
  end

  test "the book and its editions go; its readings and reviews move to the book kept" do
    edition = @dupe.editions.first
    reading = Reading.create!(work: @dupe, edition:, copy: edition.copies.first, status: "completed")
    review = Review.create!(work: @dupe, reading:, text: "Visceral.")

    WorkRemoval.run(@dupe, move_to: @kept)

    assert_not Work.exists?(@dupe.id)
    assert_not Edition.exists?(edition.id)
    assert_equal [ @kept, @kept.editions.first ], [ reading.reload.work, reading.edition ]
    assert_equal @kept, review.reload.work
    assert_equal "Removed “Books of Blood Volume 1” from the catalogue (its readings and reviews moved to “Books of Blood Volume One”)",
                 CatalogueEvent.last.summary
  end

  test "an edition another book shares stays; reviews are never deleted with the book" do
    omnibus = @dupe.editions.first
    EditionContent.create!(work: @kept, edition: omnibus)
    Review.create!(work: @dupe, text: "Visceral.")

    assert_raises(WorkRemoval::Refused) { WorkRemoval.run(@dupe) }

    @dupe.reviews.destroy_all
    WorkRemoval.run(@dupe)
    assert Edition.exists?(omnibus.id)
    assert_equal [ @kept ], omnibus.reload.works.to_a
  end
end
