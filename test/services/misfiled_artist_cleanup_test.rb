require "test_helper"

class MisfiledArtistCleanupTest < ActiveSupport::TestCase
  def book(title, *authors, cover_artist: nil, isfdb_artist: nil)
    work = Work.create!(title:, literary_form: "novel")
    authors.each_with_index { |a, i| work.work_contributors.create!(contributor: Contributor.find_or_create_by!(name: a), role: "author", display_order: i) }
    edition = Edition.create!(cover_artist:)
    EditionContent.create!(work:, edition:)
    work.provider_editions.create!(provider: "isfdb", provider_id: "p#{work.id}", cover_artist: isfdb_artist) if isfdb_artist
    work
  end

  test "a co-author ISFDB credits with the cover, or a pure cover artist, is moved; writers who also paint are left" do
    slan = book("Slan", "A.E. van Vogt", "Chris Foss", isfdb_artist: "Chris Foss")
    horizon = book("Beyond This Horizon", "Robert A. Heinlein", "Peter Andrew Jones")
    book("Other", "Someone", cover_artist: "Peter Andrew Jones") # makes him a known artist
    roberts = book("Anthology", "Editor X", "Keith Roberts")
    book("Pavane", "Keith Roberts", cover_artist: "Keith Roberts") # he writes too

    assert_equal 2, MisfiledArtistCleanup.apply

    assert_equal [ "A.E. van Vogt" ], slan.reload.authors.map(&:name)
    assert_equal [ "Robert A. Heinlein" ], horizon.reload.authors.map(&:name)
    assert_equal "Peter Andrew Jones", horizon.editions.first.cover_artist # the credit kept, on the edition
    assert_equal [ "Editor X", "Keith Roberts" ], roberts.reload.authors.map(&:name)
    assert_not Contributor.exists?(name: "Chris Foss") # no books left
    assert_match(/Moved 2 cover-artist credits/, CatalogueEvent.last.summary)
  end
end
