require "test_helper"

module Ui
  class FieldDiffComponentTest < ViewComponent::TestCase
    test "renders the field name, current, and proposed values" do
      render_inline(FieldDiffComponent.new(field: :publish_date, current: "2011", proposed: "2016-12", source: "isfdb"))

      assert_text "Publish date"
      assert_text "2011"
      assert_text "2016-12"
      assert_text "isfdb"
    end

    test "shows (blank) rather than an empty cell when current is nil" do
      render_inline(FieldDiffComponent.new(field: :language, current: nil, proposed: "eng"))

      assert_text "(blank)"
    end

    test "doesn't render a source badge when none is given" do
      render_inline(FieldDiffComponent.new(field: :publisher, current: "A", proposed: "B"))

      assert_no_selector "span", text: "isfdb"
    end
  end
end
