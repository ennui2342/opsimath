require "test_helper"

class AuthorityTermTest < ActiveSupport::TestCase
  test "a new term carries a self-variant so resolve matches the preferred form" do
    term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")

    assert_equal 1, term.authority_variants.count
    assert_equal "Tor.com", Authority.resolve("publisher", "Tor.com")
    assert_equal "Tor.com", Authority.resolve("publisher", "tor . com")
  end

  test "register_variant is idempotent and normalises" do
    term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")
    a = term.register_variant("Tordotcom")
    b = term.register_variant("TORDOTCOM")

    assert_equal a.id, b.id
    assert_equal "Tor.com", Authority.resolve("publisher", "Tordotcom")
  end

  test "register_variant raises rather than re-point a string already used by another term" do
    tor = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")
    tor.register_variant("Tordotcom")
    other = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Doherty")

    assert_raises(AuthorityTerm::Conflict) { other.register_variant("Tordotcom") }
  end

  test "the uniqueness of a normalised label is scoped to its vocabulary, not global" do
    pub = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Orbit")
    pub.register_variant("Orbit Books")

    # a second vocabulary could hold "orbit" as its own thing without clashing
    clash = AuthorityVariant.new(authority_term: pub, vocabulary: "series", label: "Orbit", normalized_label: "orbit")
    assert clash.valid?, clash.errors.full_messages.to_sentence
  end

  test "renaming the preferred label moves the self-variant with it" do
    term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tordotcom")
    term.register_variant("Tor Publishing")
    term.update!(preferred_label: "Tor.com")

    assert_equal "Tor.com", Authority.resolve("publisher", "Tor.com")
    assert_nil Authority.resolve("publisher", "Tordotcom") # the old preferred is no longer a variant
    assert_equal "Tor.com", Authority.resolve("publisher", "Tor Publishing") # other variants unaffected
  end

  test "vocabulary must be one the registry knows" do
    term = AuthorityTerm.new(vocabulary: "nonsense", preferred_label: "X")
    assert_not term.valid?
    assert_includes term.errors[:vocabulary], "is not included in the list"
  end

  test "preferred_label is unique within a vocabulary" do
    AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")
    dup = AuthorityTerm.new(vocabulary: "publisher", preferred_label: "Tor.com")
    assert_not dup.valid?
  end
end
