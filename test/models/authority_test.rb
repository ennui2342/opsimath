require "test_helper"

class AuthorityTest < ActiveSupport::TestCase
  test "normalize folds case, the and/& connector and punctuation" do
    assert_equal "faberfaber", Authority.normalize("Faber & Faber")
    assert_equal "faberfaber", Authority.normalize("Faber and Faber")
    assert_equal "harpervoyageruk", Authority.normalize("Harper Voyager (UK)")
    assert_equal "torcom", Authority.normalize("Tor.com")
  end

  test "resolve returns the preferred label for a variant, nil for an unknown string" do
    term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Millennium")
    term.register_variant("Millenium") # the common typo

    assert_equal "Millennium", Authority.resolve("publisher", "Millenium")
    assert_equal "Millennium", Authority.resolve("publisher", "MILLENNIUM")
    assert_nil Authority.resolve("publisher", "Gollancz")
    assert_nil Authority.resolve("publisher", nil)
  end

  test "handler looks up the registered vocabulary handler" do
    assert_equal Authority::Publishers, Authority.handler("publisher")
    assert Authority.vocabulary?("publisher")
    assert_not Authority.vocabulary?("weather")
  end
end
