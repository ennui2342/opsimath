require "test_helper"

class TitleWordsTest < ActiveSupport::TestCase
  test "one rule: apostrophes, numbers as digits, words or Roman numerals, and volume words" do
    assert_equal "the years best science fiction 2", TitleWords.fold("The Year's Best Science Fiction No. 2")
    assert_equal "the years best science fiction 2", TitleWords.fold("The Years Best Science Fiction 2")
    assert_equal "dangerous visions 2", TitleWords.fold("Dangerous Visions II")
    assert_equal "best sf 2", TitleWords.fold("Best SF Two")
    assert_equal "i robot", TitleWords.fold("I, Robot")
    assert_equal "the past through tomorrow 2", TitleWords.fold("The Past Through Tomorrow: Vol. 2")
    assert_equal "no blade of grass", TitleWords.fold("No Blade of Grass") # "No" only before a number
    assert_equal TitleWords.fold("Machines and Men"), TitleWords.fold("Machines & Men")
  end

  test "the matcher behind the edition picker and the nightly lookups uses it" do
    isfdb = Providers::Work.new(provider: "isfdb", id: "1", title: "The Year's Best Science Fiction No. 2", authors: [ "Harry Harrison", "Brian W. Aldiss" ])

    assert_equal [ isfdb ], WorkMatcher.match([ isfdb ], title: "The Year's Best Science Fiction 2", author: "Brian W. Aldiss")
  end
end
