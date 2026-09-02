require "test_helper"

class IsbnTest < ActiveSupport::TestCase
  test "to_13 derives the ISBN-13 with a 978 prefix and recomputed check digit" do
    assert_equal "9780441569595", Isbn.to_13("0441569595")
    assert_equal "9780802138255", Isbn.to_13("080213825X") # X check digit on the source
  end

  test "to_13 tolerates hyphens and spaces" do
    assert_equal "9780441569595", Isbn.to_13("0-441-56959-5")
    assert_equal "9780441569595", Isbn.to_13(" 0441569595 ")
  end

  test "to_13 returns nil for a non-ISBN-10 or a bad check digit" do
    assert_nil Isbn.to_13("junk")
    assert_nil Isbn.to_13("0441569590") # wrong check digit
    assert_nil Isbn.to_13("9780441569595") # already an ISBN-13
  end

  test "to_10 reverses a 978 ISBN-13" do
    assert_equal "0441569595", Isbn.to_10("9780441569595")
  end

  test "to_10 returns nil for a 979 prefix (no ISBN-10 equivalent) and for bad input" do
    assert_nil Isbn.to_10("9791234567896")
    assert_nil Isbn.to_10("junk")
  end

  test "round trips" do
    assert_equal "0441172717", Isbn.to_10(Isbn.to_13("0441172717"))
  end

  test "validation" do
    assert Isbn.valid_10?("0441569595")
    assert Isbn.valid_13?("9780441569595")
    assert_not Isbn.valid_10?("0441569590")
    assert_not Isbn.valid_13?("9780441569590")
  end
end
