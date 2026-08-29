require "test_helper"

module Reviews
  class MarkdownTest < ActiveSupport::TestCase
    test "blank input returns nil" do
      assert_nil Markdown.from_html(nil)
      assert_nil Markdown.from_html("")
      assert_nil Markdown.from_html("   ")
    end

    test "Goodreads <br><br> paragraph breaks become blank-line-separated Markdown" do
      html = "First paragraph.<br /><br />Second paragraph.<br/><br/>Third."

      assert_equal "First paragraph.\n\nSecond paragraph.\n\nThird.", Markdown.from_html(html)
    end

    test "a single lone <br> is also treated as a paragraph break, not a hard break" do
      assert_equal "Line one.\n\nLine two.", Markdown.from_html("Line one.<br/>Line two.")
    end

    test "runs of newlines are collapsed and surrounding whitespace trimmed" do
      assert_equal "Only paragraph.", Markdown.from_html("  <br/><br/>Only paragraph.<br/><br/>  ")
    end

    test "real formatting tags are converted rather than dropped" do
      md = Markdown.from_html("An <i>emphasised</i> and <b>bold</b> phrase with a <a href=\"https://example.com\">link</a>.")

      assert_equal "An _emphasised_ and **bold** phrase with a [link](https://example.com).", md
    end

    test "the per-story star pattern in a collection review survives conversion" do
      html = "Intro.<br /><br />The Very Slow Time Machine ⭐⭐⭐⭐⭐<br /><br />A time machine appears."
      md = Markdown.from_html(html)

      assert_equal "Intro.\n\nThe Very Slow Time Machine ⭐⭐⭐⭐⭐\n\nA time machine appears.", md
    end

    test "plain prose with no markup passes through unchanged" do
      assert_equal "Just one paragraph, nothing special.", Markdown.from_html("Just one paragraph, nothing special.")
    end
  end
end
