require "test_helper"

module Ui
  class MarkdownComponentTest < ViewComponent::TestCase
    test "renders Markdown paragraphs and inline formatting" do
      render_inline(MarkdownComponent.new(text: "First para with _emphasis_ and **weight**.\n\nSecond para."))

      assert_selector "div.markdown p", count: 2
      assert_selector "p em", text: "emphasis"
      assert_selector "p strong", text: "weight"
    end

    test "renders links with their href" do
      render_inline(MarkdownComponent.new(text: "See [the site](https://example.com)."))

      assert_selector "a[href='https://example.com']", text: "the site"
    end

    test "strips disallowed HTML that appears in the stored Markdown" do
      render_inline(MarkdownComponent.new(text: "Fine text.\n\n<script>alert('x')</script>\n\n<img src=x onerror=1>"))

      assert_no_selector "script"
      assert_no_selector "img"
      assert_text "Fine text."
    end

    test "does not render at all for blank text" do
      render_inline(MarkdownComponent.new(text: nil))
      assert_no_selector "div.markdown"

      render_inline(MarkdownComponent.new(text: "   "))
      assert_no_selector "div.markdown"
    end
  end
end
