require "test_helper"

class PendingDecisionSweepTest < ActiveSupport::TestCase
  setup do
    @edition = Edition.create!(publisher: "Random House Worlds", page_count: nil)
    @record = EnrichmentRecord.create!(entity: @edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {},
                                       fields: { "publisher" => "Bantam Spectra", "page_count" => 496 })
    @decision = conflict(%w[publisher page_count])
  end

  def conflict(fields, source: "isfdb", edition: @edition)
    PendingDecision.create!(kind: "enrichment_conflict", payload: { entity_type: "Edition", entity_id: edition.id, source:, fields: })
  end

  test "a live disagreement stays pending" do
    assert_empty PendingDecisionSweep.all
    assert @decision.reload.pending?
  end

  test "once every disputed field agrees, the decision is closed as accepted" do
    @edition.update!(publisher: "Bantam Spectra")
    PendingDecisionSweep.all
    assert @decision.reload.pending? # page count still differs

    @edition.update!(page_count: 496)
    assert_equal({ "accepted" => 1 }, PendingDecisionSweep.all)
    assert @decision.reload.accepted?
  end

  test "a publisher variant the authority file maps to the edition's publisher agrees" do
    @edition.update!(page_count: 496)
    AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Random House Worlds").register_variant("Bantam Spectra")

    PendingDecisionSweep.all

    assert @decision.reload.accepted?
  end

  test "a source record that's gone, or an edition that's gone, leaves nothing to decide" do
    goodreads = conflict(%w[publisher], source: "goodreads") # no goodreads record on file
    PendingDecisionSweep.for_edition(@edition.id)
    assert goodreads.reload.rejected?

    @edition.destroy!
    assert @decision.reload.rejected?
  end

  test "the review screen's accept settles other sources' decisions it made moot" do
    other = conflict(%w[publisher], source: "openlibrary")
    EnrichmentRecord.create!(entity: @edition, provider: "openlibrary", external_id: "OL1M", fetched_at: Time.current, raw_payload: {},
                             fields: { "publisher" => "Bantam Spectra" })

    Enrichment::PendingDecisionResolver.accept(@decision, selected_fields: %w[publisher page_count])

    assert other.reload.accepted?
  end

  test "the metadata cog settles a decision it made moot" do
    Enrichment::EditionMetadataResolver.apply(@edition, picks: %w[isfdb:publisher isfdb:page_count])

    assert @decision.reload.accepted?
  end
end
