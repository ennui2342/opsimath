require "test_helper"

module Ui
  class RecordComparisonComponentTest < ViewComponent::TestCase
    DIFFS = [
      { field: "publisher", current: "St Martins Pr", proposed: "HarperVoyager", source: "isfdb" },
      { field: "publish_date", current: nil, proposed: "2016-12", source: "isfdb" }
    ].freeze

    test "renders every field in both the current and proposed columns" do
      render_inline(RecordComparisonComponent.new(diffs: DIFFS))

      assert_text "Current"
      assert_text "Proposed"
      assert_text "St Martins Pr"
      assert_text "HarperVoyager"
      assert_text "2016-12"
    end

    test "shows (blank) rather than an empty cell when current is nil" do
      render_inline(RecordComparisonComponent.new(diffs: DIFFS))

      assert_text "(blank)"
    end

    test "renders a checked-by-default fields[] checkbox per field, only on the proposed side" do
      render_inline(RecordComparisonComponent.new(diffs: DIFFS))

      assert_selector "input[type=checkbox][name='fields[]'][value=publisher][checked]"
      assert_selector "input[type=checkbox][name='fields[]'][value=publish_date][checked]"
      assert_selector "input[type=checkbox]", count: 2
    end

    test "renders an 'also on file' line for a field with a known other-provider candidate" do
      diffs = [ DIFFS.first.merge(other_candidates: [ { provider: "goodreads", value: "HarperVoyager UK" } ]) ]

      render_inline(RecordComparisonComponent.new(diffs: diffs))

      assert_text "Also on file: goodreads: HarperVoyager UK"
    end

    test "renders no 'also on file' line when there isn't one" do
      render_inline(RecordComparisonComponent.new(diffs: DIFFS))

      assert_no_text "Also on file"
    end
  end
end
