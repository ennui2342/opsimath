require "test_helper"

module Enrichment
  class PendingDecisionResolverTest < ActiveSupport::TestCase
    test "accepting an isolated enrichment_field_conflict applies the proposed value and sets field_sources" do
      edition = Edition.create!(publisher: "St Martins Pr")
      pending = PendingDecision.create!(
        kind: "enrichment_field_conflict",
        payload: {
          "entity_type" => "Edition", "entity_id" => edition.id, "field" => "publisher",
          "current_value" => "St Martins Pr", "proposed" => [ { "value" => "HarperVoyager", "source" => "isfdb" } ]
        }
      )

      PendingDecisionResolver.accept(pending)

      edition.reload
      assert_equal "HarperVoyager", edition.publisher
      assert_equal "isfdb", edition.field_sources["publisher"]
      assert_equal "accepted", pending.reload.status
      assert pending.resolved_at.present?
    end

    test "accepting a bundled enrichment_edition_mismatch applies every field in the bundle" do
      edition = Edition.create!(publisher: "St Martins Pr", publish_date: "2011")
      pending = PendingDecision.create!(
        kind: "enrichment_edition_mismatch",
        payload: {
          "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb",
          "fields" => [
            { "field" => "publisher", "current_value" => "St Martins Pr", "proposed" => "HarperVoyager (UK)" },
            { "field" => "publish_date", "current_value" => "2011", "proposed" => "2016-12" }
          ]
        }
      )

      PendingDecisionResolver.accept(pending)

      edition.reload
      assert_equal "HarperVoyager (UK)", edition.publisher
      assert_equal "2016-12", edition.publish_date
      assert_equal "isfdb", edition.field_sources["publisher"]
      assert_equal "isfdb", edition.field_sources["publish_date"]
      assert_equal "accepted", pending.reload.status
    end

    test "rejecting leaves the entity untouched but resolves the decision" do
      edition = Edition.create!(publisher: "St Martins Pr")
      pending = PendingDecision.create!(
        kind: "enrichment_field_conflict",
        payload: {
          "entity_type" => "Edition", "entity_id" => edition.id, "field" => "publisher",
          "current_value" => "St Martins Pr", "proposed" => [ { "value" => "HarperVoyager", "source" => "isfdb" } ]
        }
      )

      PendingDecisionResolver.reject(pending)

      assert_equal "St Martins Pr", edition.reload.publisher
      assert_equal "rejected", pending.reload.status
      assert pending.resolved_at.present?
    end

    test "a kind with no known automatic action only changes status, never touches an entity" do
      edition = Edition.create!(publisher: "St Martins Pr")
      pending = PendingDecision.create!(
        kind: "reread_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "goodreads_book_id" => "1" }
      )

      PendingDecisionResolver.accept(pending)

      assert_equal "St Martins Pr", edition.reload.publisher
      assert_equal "accepted", pending.reload.status
    end
  end
end
