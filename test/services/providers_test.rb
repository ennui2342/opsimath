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

    assert_equal [ work ], Providers.search_works(title: "Crossfire", providers: [ good, bad ])
  end
end
