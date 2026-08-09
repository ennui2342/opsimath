require "test_helper"

module Enrichment
  class PendingDecisionResolverTest < ActiveSupport::TestCase
    # field_diffs now derives current/proposed live from the entity's
    # column plus the named source's latest EnrichmentRecord — so every
    # test naming a real (non-cover) field needs a backing
    # EnrichmentRecord with that value in its fields column, not just a
    # payload asserting the value directly.
    def enrichment_record!(entity, provider: "isfdb", fields:)
      EnrichmentRecord.create!(entity: entity, provider: provider, external_id: "1", fetched_at: Time.current, raw_payload: {}, fields: fields)
    end

    test "accepting a single-field enrichment_conflict applies the proposed value and sets field_sources" do
      edition = Edition.create!(publisher: "St Martins Pr")
      enrichment_record!(edition, fields: { "publisher" => "HarperVoyager" })
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
      )

      PendingDecisionResolver.accept(pending)

      edition.reload
      assert_equal "HarperVoyager", edition.publisher
      assert_equal "isfdb", edition.field_sources["publisher"]
      assert_equal "accepted", pending.reload.status
      assert pending.resolved_at.present?
    end

    test "accepting a bundled enrichment_conflict applies every field in the bundle" do
      edition = Edition.create!(publisher: "St Martins Pr", publish_date: "2011")
      enrichment_record!(edition, fields: { "publisher" => "HarperVoyager (UK)", "publish_date" => "2016-12" })
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "publisher", "publish_date" ] }
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
      enrichment_record!(edition, fields: { "publisher" => "HarperVoyager (UK)", "publish_date" => "2016-12" })
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "publisher", "publish_date" ] }
      )

      PendingDecisionResolver.accept(pending, selected_fields: [ "publisher" ])

      edition.reload
      assert_equal "HarperVoyager (UK)", edition.publisher
      assert_equal "2011", edition.publish_date # not selected, untouched
      assert_equal "accepted", pending.reload.status
      assert_equal [ "publisher" ], pending.payload["fields"]
    end

    test "raises rather than silently accepting when the named source has no backing EnrichmentRecord" do
      edition = Edition.create!(publisher: "St Martins Pr")
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
      )

      assert_raises(RuntimeError) { PendingDecisionResolver.accept(pending) }

      assert_equal "St Martins Pr", edition.reload.publisher # never touched
      assert_equal "pending", pending.reload.status # never silently marked accepted
    end

    test "accepting a cover field attaches the source's EnrichmentRecord cover onto the edition" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      record = enrichment_record!(edition, fields: {})
      record.cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "cover_image" ] }
      )

      PendingDecisionResolver.accept(pending)

      edition.reload
      assert_equal "new-bytes", edition.cover_image.download
      assert_equal "isfdb", edition.field_sources["cover_image"] # now protected on a future re-enrichment pass
      assert record.reload.cover_image.attached? # the source's own copy is untouched — just shared, not moved
    end

    test "leaving the cover unchecked while accepting other fields leaves cover_image untouched" do
      edition = Edition.create!(publisher: "St Martins Pr")
      record = enrichment_record!(edition, fields: { "publisher" => "HarperVoyager" })
      edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      record.cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "publisher", "cover_image" ] }
      )

      PendingDecisionResolver.accept(pending, selected_fields: [ "publisher" ])

      edition.reload
      assert_equal "HarperVoyager", edition.publisher
      assert_equal "old-bytes", edition.cover_image.download # untouched
    end

    test "rejecting a cover decision leaves the edition's cover and the source's EnrichmentRecord untouched" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("old-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      record = enrichment_record!(edition, fields: {})
      record.cover_image.attach(io: StringIO.new("new-bytes"), filename: "new.jpg", content_type: "image/jpeg")
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "source" => "isfdb", "fields" => [ "cover_image" ] }
      )

      PendingDecisionResolver.reject(pending)

      assert_equal "old-bytes", edition.reload.cover_image.download
      assert record.reload.cover_image.attached? # the source's own copy persists regardless
      assert_equal "rejected", pending.reload.status
    end

    test "rejecting leaves the entity untouched but resolves the decision" do
      edition = Edition.create!(publisher: "St Martins Pr")
      enrichment_record!(edition, fields: { "publisher" => "HarperVoyager" })
      pending = PendingDecision.create!(
        kind: "enrichment_conflict",
        payload: { "entity_type" => "Edition", "entity_id" => edition.id, "fields" => [ "publisher" ], "source" => "isfdb" }
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
