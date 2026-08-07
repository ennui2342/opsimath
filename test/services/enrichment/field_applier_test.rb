require "test_helper"

module Enrichment
  class FieldApplierTest < ActiveSupport::TestCase
    setup do
      @edition = Edition.create!(format: "paperback")
    end

    test "applies a value to a genuinely blank field and records field_sources" do
      result = FieldApplier.apply(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal :applied, result.status
      assert_equal "Ace Books", @edition.reload.publisher
      assert_equal "isfdb", @edition.field_sources["publisher"]
    end

    test "does nothing when the proposed value is blank" do
      result = FieldApplier.apply(@edition, :publisher, "", "isfdb")

      assert_equal :skipped, result.status
      assert_nil @edition.reload.publisher
    end

    test "is a no-op when the field already holds the same value" do
      @edition.update!(publisher: "Ace Books")

      result = FieldApplier.apply(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal :unchanged, result.status
      assert_equal 0, PendingDecision.count
    end

    test "is a no-op when the values only differ by case/whitespace/punctuation — not a real conflict" do
      @edition.update!(publisher: "Pan/Ballantine")

      result = FieldApplier.apply(@edition, :publisher, "Pan / Ballantine", "isfdb")

      assert_equal :unchanged, result.status
      assert_equal "Pan/Ballantine", @edition.reload.publisher # untouched, but also not flagged
      assert_equal 0, PendingDecision.count
    end

    test "creates a PendingDecision rather than overwriting a genuinely conflicting non-empty field" do
      @edition.update!(publisher: "Berkley Windhover")

      result = FieldApplier.apply(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal :pending, result.status
      assert_equal "Berkley Windhover", @edition.reload.publisher # untouched
      assert_nil @edition.field_sources["publisher"] # never set — no value was ever applied

      decision = result.pending_decision
      assert_equal "enrichment_field_conflict", decision.kind
      assert_equal "pending", decision.status
      assert_equal "Edition", decision.payload["entity_type"]
      assert_equal @edition.id, decision.payload["entity_id"]
      assert_equal [ "publisher" ], decision.payload["fields"]
      assert_equal "isfdb", decision.payload["source"]
    end

    test "re-flagging the same conflict reuses the existing pending decision rather than duplicating it" do
      @edition.update!(publisher: "Berkley Windhover")

      first = FieldApplier.apply(@edition, :publisher, "Ace Books", "isfdb")
      second = FieldApplier.apply(@edition, :publisher, "Ace Books", "isfdb")

      assert_equal 1, PendingDecision.count
      assert_equal first.pending_decision.id, second.pending_decision.id
    end
  end
end
