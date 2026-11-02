require "test_helper"

module Ui
  class EditionChoiceCardComponentTest < ViewComponent::TestCase
    def card(*editions) = AddBook::EditionCards::Card.new(editions:)

    test "publisher and years first, then format and artist, then ISBN and sources, as a radio" do
      c = card(Providers::Edition.new(provider: "isfdb", id: "2", publisher: "Orbit", publish_date: "1979", binding: "pb",
                                      cover_artist: "Peter Jones", isbn10: "0860079422", cover_url: "https://covers.test/2.jpg"),
               Providers::Edition.new(provider: "openlibrary", id: "OL1M", publisher: "Futura"))

      render_inline(EditionChoiceCardComponent.new(card: c, token: "tok", work_title: "The Birthgrave"))

      assert_selector "input[type=radio][name=card][value=tok]"
      assert_text "Orbit · 1979"
      assert_text "Mass-market paperback · Peter Jones"
      assert_text "#{Isbn.to_13("0860079422")} · ISFDB + Open Library"
      assert_selector "img[src='https://covers.test/2.jpg']"
    end

    test "an omnibus printing shows its own title" do
      c = card(Providers::Edition.new(provider: "isfdb", id: "9", publisher: "Gollancz", title: "Peace and War"))

      render_inline(EditionChoiceCardComponent.new(card: c, token: "t", work_title: "The Forever War"))

      assert_text "Peace and War"
    end
  end
end
