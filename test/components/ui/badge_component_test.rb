require "test_helper"

module Ui
  class BadgeComponentTest < ViewComponent::TestCase
    test "renders the given text" do
      render_inline(BadgeComponent.new(text: "Science fiction"))

      assert_text "Science fiction"
    end

    test "defaults to the default variant for an unknown variant" do
      render_inline(BadgeComponent.new(text: "x", variant: :nonsense))

      assert_selector "span.bg-gray-100"
    end

    test "conflict variant uses the conflict theme tokens" do
      render_inline(BadgeComponent.new(text: "enrichment_field_conflict", variant: :conflict))

      assert_selector "span.bg-conflict-100.text-conflict-800"
    end
  end
end
