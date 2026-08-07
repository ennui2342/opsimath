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

    test "partial accept only applies the selected fields and prunes the payload to match" do
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

      PendingDecisionResolver.accept(pending, selected_fields: [ "publisher" ])

      edition.reload
      assert_equal "HarperVoyager (UK)", edition.publisher
      assert_equal "2011", edition.publish_date # not selected, untouched
      assert_equal "accepted", pending.reload.status
      assert_equal [ "publisher" ], pending.payload["fields"].map { |f| f["field"] }
    end

    test "accepting a cover field attaches the candidate to cover_image and detaches (not purges) it" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      edition.candidate_cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      candidate_blob_id = edition.candidate_cover_image.blob.id
      pending = PendingDecision.create!(
        kind: "enrichment_edition_mismatch",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ { "field" => "cover_image" } ] }
      )

      PendingDecisionResolver.accept(pending)

      edition.reload
      assert_equal "new-bytes", edition.cover_image.download
      assert_not edition.candidate_cover_image.attached?
      assert_equal "isfdb", edition.field_sources["cover_image"] # now protected on a future re-enrichment pass
      assert ActiveStorage::Blob.exists?(candidate_blob_id) # the blob itself survives — cover_image now shares it
    end

    test "leaving the cover unchecked while accepting other fields purges the candidate and leaves cover_image untouched" do
      edition = Edition.create!(publisher: "St Martins Pr")
      edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      edition.candidate_cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      pending = PendingDecision.create!(
        kind: "enrichment_edition_mismatch",
        payload: {
          "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb",
          "fields" => [ { "field" => "publisher", "current_value" => "St Martins Pr", "proposed" => "HarperVoyager" }, { "field" => "cover_image" } ]
        }
      )

      PendingDecisionResolver.accept(pending, selected_fields: [ "publisher" ])

      edition.reload
      assert_equal "HarperVoyager", edition.publisher
      assert_equal "old-bytes", edition.cover_image.download # untouched
      assert_not edition.candidate_cover_image.attached? # purged, genuinely orphaned
    end

    test "rejecting a bundled decision with a staged candidate cover purges it" do
      edition = Edition.create!
      edition.candidate_cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      pending = PendingDecision.create!(
        kind: "enrichment_edition_mismatch",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ { "field" => "cover_image" } ] }
      )

      PendingDecisionResolver.reject(pending)

      assert_not edition.reload.candidate_cover_image.attached?
      assert_equal "rejected", pending.reload.status
    end

    test "rejecting an unrelated decision never touches a different pending decision's staged candidate cover" do
      edition = Edition.create!(publisher: "St Martins Pr")
      edition.candidate_cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      cover_pending = PendingDecision.create!(
        kind: "enrichment_edition_mismatch",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ { "field" => "cover_image" } ] }
      )
      unrelated_pending = PendingDecision.create!(
        kind: "enrichment_field_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "field" => "publisher", "current_value" => "St Martins Pr", "proposed" => [ { "value" => "HarperVoyager", "source" => "isfdb" } ] }
      )

      PendingDecisionResolver.reject(unrelated_pending)

      assert edition.reload.candidate_cover_image.attached? # still staged, belongs to cover_pending
      assert_equal "pending", cover_pending.reload.status
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

    test "accepting a reread_conflict opens a new Reading dated from the currently-reading event, leaving the old completed Reading alone" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      old_reading = Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2010, 5, 1))
      pending = PendingDecision.create!(
        kind: "reread_conflict",
        payload: { "goodreads_book_id" => "1", "title" => "Neuromancer", "work_id" => work.id, "edition_id" => edition.id, "date_started" => "2026-08-01" }
      )

      PendingDecisionResolver.accept(pending)

      assert_equal 2, work.readings.count
      new_reading = work.readings.where.not(id: old_reading.id).sole
      assert_equal "reading", new_reading.status
      assert_equal Date.new(2026, 8, 1), new_reading.date_started
      assert_equal "completed", old_reading.reload.status # untouched
      assert_equal "accepted", pending.reload.status
    end

    test "rejecting a reread_conflict does nothing beyond resolving the decision" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      Reading.create!(work: work, edition: edition, status: "completed", date_finished: Date.new(2010, 5, 1))
      pending = PendingDecision.create!(
        kind: "reread_conflict",
        payload: { "goodreads_book_id" => "1", "title" => "Neuromancer", "work_id" => work.id, "edition_id" => edition.id, "date_started" => "2026-08-01" }
      )

      PendingDecisionResolver.reject(pending)

      assert_equal 1, work.readings.count
      assert_equal "rejected", pending.reload.status
    end

    test "a kind with no known automatic action only changes status, never touches an entity" do
      edition = Edition.create!(publisher: "St Martins Pr")
      pending = PendingDecision.create!(
        kind: "possible_duplicate_work",
        payload: { "goodreads_book_id" => "1" }
      )

      PendingDecisionResolver.accept(pending)

      assert_equal "St Martins Pr", edition.reload.publisher
      assert_equal "accepted", pending.reload.status
    end
  end
end
