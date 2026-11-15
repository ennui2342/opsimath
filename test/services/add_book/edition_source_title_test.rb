require "test_helper"

module AddBook
  class EditionSourceTitleTest < ActiveSupport::TestCase
    Fast = Struct.new(:name) do
      def search_works(title:, author: nil) = [ Providers::Work.new(provider: name, id: "7", title: "Machines and Men", authors: [ "Keith Roberts" ]) ]
      def known_editions(isbns:, work_ids:) = Providers::KnownEditions.new(work_ids:, editions: [ Providers::Edition.new(provider: name, id: "p1", publisher: "Panther") ])
    end

    Hung = Struct.new(:name) do
      def search_works(title:, author: nil) = sleep(5) && []
      def known_editions(**) = Providers::KnownEditions.new(work_ids: [], editions: [])
    end

    test "a source that hangs doesn't hold the picker: what the others found comes back within the time limit" do
      work = Work.create!(title: "Machines & Men", literary_form: "collection")
      work.work_contributors.create!(contributor: Contributor.create!(name: "Keith Roberts"), role: "author")

      started = Time.now
      editions = EditionSource.by_title(work, deadline: 1, providers: [ Fast.new("isfdb"), Hung.new("openlibrary") ])

      assert_equal [ "p1" ], editions.map(&:id)
      assert_operator Time.now - started, :<, 3
    end
  end
end
