module Ui
  class MarkdownComponentPreview < ViewComponent::Preview
    # A typical converted Goodreads review — prose paragraphs.
    def review
      render(MarkdownComponent.new(text: <<~MD))
        Deckard hunts rogue androids that, with every new model, become harder to
        identify and harder to regard as artificial.

        He relies on an empathy test to catch them, but when humans use 'Mood
        Organs' to induce emotions, asking whether machines have empathy becomes
        the wrong question.
      MD
    end

    # A collection review with per-story lines and inline formatting.
    def collection_review
      render(MarkdownComponent.new(text: <<~MD))
        A collection loosely based around Vinge's early cyberpunk short,
        _True Names_, and his concept of the singularity.

        Bookworm, run! (1966) ⭐⭐

        An experimental chimp is connected to a computer. See the
        [author page](https://example.com) for more.
      MD
    end

    def blank
      render(MarkdownComponent.new(text: ""))
    end
  end
end
