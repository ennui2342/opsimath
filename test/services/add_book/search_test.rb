require "test_helper"

module AddBook
  class SearchTest < ActiveSupport::TestCase
    FakeProvider = Struct.new(:name, :works, :isbn_works) do
      def capabilities = %i[search_works]
      def search_works(title:, author: nil) = works
      def works_for_isbn(_isbn) = isbn_works
    end

    def work(provider, id, title, authors, **attrs) = Providers::Work.new(provider:, id:, title:, authors:, **attrs)

    test "one result per book across providers; a stored provider id marks it as catalogued" do
      catalogued = Work.create!(title: "Crossfire", literary_form: "novel")
      catalogued.work_identifiers.create!(id_type: "openlibrary_work", value: "OL1W")
      isfdb = FakeProvider.new("isfdb", [ work("isfdb", "1911", "Crossfire", [ "Nancy Kress" ], first_year: 2003),
                                          work("isfdb", "77", "Crossfire Trail", [ "Louis L'Amour" ]) ])
      ol = FakeProvider.new("openlibrary", [ work("openlibrary", "OL1W", "Crossfire", [ "Nancy Kress" ], cover_url: "https://c/1.jpg") ])

      results = Search.new(providers: [ isfdb, ol ]).run("crossfire kress")

      assert_equal 2, results.size
      kress = results.find { |r| r.title == "Crossfire" }
      assert_equal %w[isfdb openlibrary], kress.providers
      assert_equal [ 2003, "https://c/1.jpg" ], [ kress.first_year, kress.cover_url ]
      assert_equal catalogued, kress.work
      assert_nil results.find { |r| r.title == "Crossfire Trail" }.work
    end

    test "a book already catalogued without provider ids is found by title and author" do
      work = Work.create!(title: "The Birthgrave", literary_form: "novel")
      work.work_contributors.create!(contributor: Contributor.create!(name: "Tanith Lee"), role: "author")
      provider = FakeProvider.new("isfdb", [ work("isfdb", "5", "The Birthgrave", [ "Tanith Lee" ]) ])

      assert_equal work, Search.new(providers: [ provider ]).run("birthgrave").sole.work
    end

    test "ranked by how well title and author match; foreign-only ISFDB titles left out" do
      english = Providers::Edition.new(provider: "isfdb", id: "1", language: "eng")
      hungarian = Providers::Edition.new(provider: "isfdb", id: "2", language: "hun")
      provider = FakeProvider.new("isfdb", [
        work("isfdb", "9", "Steven Spielberg's Amazing Stories", [ "Steven Spielberg" ], editions: [ english ]),
        work("isfdb", "8", "Hackers", [ "Steven Levy" ], editions: [ english ]),
        work("isfdb", "7", "Hackers", [ "Steven Levy" ], editions: [ hungarian ]) # its translation: dropped
      ])

      results = Search.new(providers: [ provider ]).run("hackers steven levy")

      assert_equal [ "Hackers", "Steven Spielberg's Amazing Stories" ], results.map(&:title)
      assert_equal [ "8" ], results.first.provider_works.map(&:id)
    end

    test "an ISBN is looked up rather than searched" do
      provider = FakeProvider.new("isfdb", [], [ work("isfdb", "1911", "Crossfire", [ "Nancy Kress" ]) ])

      assert_equal [ "Crossfire" ], Search.new(providers: [ provider ]).run("978-0-7653-0467-4").map(&:title)
    end

    test "the payload carries a few ISBNs per provider work, or the printings when there are none" do
      ed = Providers::Edition.new(provider: "isfdb", id: "9", isbn13: "9780765304674")
      bare = Providers::Edition.new(provider: "isfdb", id: "10", publisher: "Gnome Press")
      result = Search::Result.new(title: "T", authors: [], provider_works: [ work("isfdb", "1", "T", [], editions: [ ed ]),
                                                                            work("isfdb", "2", "T", [], editions: [ bare ]) ])

      payload = result.to_payload["provider_works"]

      assert_equal [ [ "9780765304674" ], [] ], payload.map { |pw| pw["isbns"] }
      assert_equal [ 0, 1 ], payload.map { |pw| pw["editions"].size }
    end
  end
end
