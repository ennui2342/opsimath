require "test_helper"

module Enrichment
  class FieldApplierTest < ActiveSupport::TestCase
    setup do
      @edition = Edition.create!(format: "paperback")
    end

    test "plans a fill for a genuinely blank field" do
      plan = FieldApplier.plan(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal :fill, plan.action
      assert_equal "Ace Books", plan.value
      assert_equal "isfdb", plan.source
    end

    test "plans skipped when the proposed value is blank" do
      plan = FieldApplier.plan(@edition, :publisher, "", "isfdb")

      assert_equal :skipped, plan.action
    end

    test "plans unchanged when the field already holds the same value" do
      @edition.update!(publisher: "Ace Books")

      plan = FieldApplier.plan(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal :unchanged, plan.action
    end

    test "plans unchanged when the values only differ by case/whitespace/punctuation — not a real conflict" do
      @edition.update!(publisher: "Pan/Ballantine")

      plan = FieldApplier.plan(@edition, :publisher, "Pan / Ballantine", "isfdb")

      assert_equal :unchanged, plan.action
    end

    test "plans a conflict for a genuinely conflicting non-empty field" do
      @edition.update!(publisher: "Berkley Windhover")

      plan = FieldApplier.plan(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal :conflict, plan.action
      assert_equal "Berkley Windhover", plan.current
      assert_equal "Ace Books", plan.value
      assert_equal "isfdb", plan.source
    end
  end
end
