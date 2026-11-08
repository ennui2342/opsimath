require "test_helper"

class BookAddedJobTest < ActiveJob::TestCase
  test "a book added from Open Library gets ISFDB's printing and its cover artist straight away" do
    work = Work.create!(title: "Continuum 4", literary_form: "anthology")
    edition = Edition.create!(publisher: "Star Books", field_sources: { "publisher" => "openlibrary" })
    EditionContent.create!(work:, edition:)
    edition.edition_identifiers.create!(id_type: "isbn13", value: "9780352396396")
    edition.edition_identifiers.create!(id_type: "openlibrary", value: "OL28174451M")
    # The lookup itself (KnownEditionsRefresh) is tested on its own; here it finds ISFDB's printing.
    original = KnownEditionsRefresh.method(:refresh_work)
    KnownEditionsRefresh.define_singleton_method(:refresh_work) do |w|
      w.provider_editions.create!(provider: "isfdb", provider_id: "163031", isbn13: "9780352396396", publisher: "Star", binding: "pb",
                                  publish_date: "1977-06", cover_artist: "Patrick Woodroffe")
    end
    begin
      BookAddedJob.perform_now(work.id)
    ensure
      KnownEditionsRefresh.define_singleton_method(:refresh_work, original)
    end

    edition.reload
    assert_equal [ "Patrick Woodroffe", "Star" ], [ edition.cover_artist, edition.publisher ]
    assert edition.edition_identifiers.exists?(id_type: "isfdb", value: "163031")
  end
end
