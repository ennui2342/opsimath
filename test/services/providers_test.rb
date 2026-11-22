require "test_helper"

class ProvidersTest < ActiveSupport::TestCase
  Fake = Struct.new(:name, :result, :error) do
    def capabilities = %i[search_works]

    def search_works(title:, author: nil)
      raise error if error

      result
    end
  end

  test "the registry knows ISFDB and Open Library and what each can do" do
    assert_equal %w[isfdb openlibrary], Providers.with(:known_editions).map(&:name)
    assert_equal "openlibrary", Providers.find("openlibrary").name
  end

  test "search fans out; a failing provider contributes nothing rather than failing the search" do
    work = Providers::Work.new(provider: "a", id: "1", title: "Crossfire")
    good = Fake.new("a", [ work ])
    bad = Fake.new("b", nil, RuntimeError.new("down"))

    missed = []
    assert_equal [ work ], Providers.search_works(title: "Crossfire", providers: [ good, bad ], missed:)
    assert_equal [ "b" ], missed # said so, not taken for "no such book"
  end

  test "a provider that doesn't answer in time is cut off and named as missed" do
    slow = Fake.new("isfdb", [])
    def slow.search_works(title:, author: nil) = sleep(5) && []
    missed = []

    assert_equal [], Providers.search_works(title: "The Second Trip", providers: [ slow ], missed:, timeout: 0.2.seconds)
    assert_equal [ "isfdb" ], missed
  end
end
