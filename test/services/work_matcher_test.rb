require "test_helper"

class WorkMatcherTest < ActiveSupport::TestCase
  def w(id, title, authors, languages = [ "eng" ]) = Providers::Work.new(provider: "x", id:, title:, authors: Array(authors), languages:)

  test "one title and author: that work" do
    works = [ w(1957, "The Fifth Head of Cerberus", "Gene Wolfe"), w(9, "The Wolfe at the Door", "Gene Wolfe") ]

    assert_equal [ 1957 ], WorkMatcher.match(works, title: "The Fifth Head of Cerberus", author: "Gene Wolfe").map(&:id)
  end

  test "a same-titled translation and an adaptation don't make it ambiguous" do
    lexicon = [ w(1, "Lexicon", "Max Barry", [ "ger" ]), w(2, "Lexicon", "Max Barry", [ "dut" ]), w(3, "Lexicon", "Max Barry") ]
    kindred = [ w(4, "Kindred", "Octavia E. Butler"), w(5, "Kindred: A Graphic Novel Adaptation", [ "Octavia E. Butler", "Damian Duffy" ]) ]

    assert_equal [ 3 ], WorkMatcher.match(lexicon, title: "Lexicon", author: "Max Barry").map(&:id)
    assert_equal [ 4 ], WorkMatcher.match(kindred, title: "Kindred", author: "Octavia E. Butler").map(&:id)
  end

  test "the same book credited two ways is taken together; different volumes are not guessed between" do
    paradise = [ w(6, "The Paradise Game", "Brian M. Stableford"), w(7, "The Paradise Game", "Brian Stableford") ]
    past = [ w(8, "The Past Through Tomorrow: Vol. 1", "Robert A. Heinlein"), w(9, "The Past Through Tomorrow: Book One", "Robert A. Heinlein") ]

    assert_equal [ 6, 7 ], WorkMatcher.match(paradise, title: "The Paradise Game", author: "Brian M. Stableford").map(&:id)
    assert_empty WorkMatcher.match(past, title: "The Past Through Tomorrow: Vol. 2", author: "Robert A. Heinlein")
  end

  test "another author's book of the same title is not ours; folding handles punctuation" do
    assert_empty WorkMatcher.match([ w(1, "Summerland", "Jackie French") ], title: "Summerland", author: "Hannu Rajaniemi")
    assert_equal [ 2 ], WorkMatcher.match([ w(2, "Cat’s Cradle", "Kurt Vonnegut") ], title: "Cat's Cradle", author: "Kurt Vonnegut, Jr.").map(&:id)
    assert_equal [ 3 ], WorkMatcher.match([ w(3, "The Futurological Congress", "Stanisław Lem") ], title: "Futurological Congress", author: "Stanislaw Lem").map(&:id)
  end

  test "a title with a bracketed note matches records of the plain title, taken together" do
    syndic = ->(id, author) { Providers::Work.new(provider: "isfdb", id:, title: "The Syndic", authors: [ author ], editions: []) }
    works = [ syndic.("1060", "C. M. Kornbluth"), syndic.("731977", "Cyril M. Kornbluth") ]

    assert_equal %w[1060 731977], WorkMatcher.match(works, title: "The Syndic (Sphere science fiction)", author: "C.M. Kornbluth").map(&:id)
    assert_equal "The Syndic", WorkMatcher.plain("The Syndic (Sphere science fiction)")
  end
end
