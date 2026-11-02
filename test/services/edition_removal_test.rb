require "test_helper"

class EditionRemovalTest < ActiveSupport::TestCase
  setup do
    @work = Work.create!(title: "Hackers", literary_form: "novel")
    @keep, @dupe = 2.times.map do |i|
      Edition.create!(publisher: "HarperCollins #{i}").tap { |e| EditionContent.create!(work: @work, edition: e) }
    end
    @copy = Copy.create!(edition: @dupe, disposition: "owned")
    @reading = Reading.create!(work: @work, edition: @dupe, copy: @copy, status: "completed", source: "owned_copy", date_finished: Date.new(2026, 10, 30))
    @review = Review.create!(work: @work, reading: @reading, text: "Good.", status: "draft")
    @decision = PendingDecision.create!(kind: "enrichment_conflict", payload: { entity_type: "Edition", entity_id: @dupe.id, source: "isfdb", fields: [ "publisher" ] })
  end

  test "a duplicate goes; its copies and readings move to the edition kept" do
    EditionRemoval.run(@dupe, work: @work, move_to: @keep)

    assert_not Edition.exists?(@dupe.id)
    assert_equal [ @keep ], @work.reload.editions.to_a
    assert_equal [ @keep, @keep ], [ @copy.reload.edition, @reading.reload.edition ]
    assert_equal @copy, @reading.copy
    assert @decision.reload.rejected?
  end

  test "one added by mistake goes with its copies and readings; reviews stay with the book" do
    EditionRemoval.run(@dupe, work: @work)

    assert_not Copy.exists?(@copy.id)
    assert_not Reading.exists?(@reading.id)
    assert_equal @work, @review.reload.work
    assert_nil @review.reading
  end

  test "refused for a book's only edition, an edition another book shares, or moving to a stranger" do
    EditionRemoval.run(@dupe, work: @work, move_to: @keep)
    assert_raises(EditionRemoval::Refused) { EditionRemoval.run(@keep, work: @work) }

    other = Work.create!(title: "Omnibus", literary_form: "novel")
    shared = Edition.create!.tap { |e| [ @work, other ].each { |w| EditionContent.create!(work: w, edition: e) } }
    assert_raises(EditionRemoval::Refused) { EditionRemoval.run(shared, work: @work, move_to: @keep) }

    stranger = Edition.create!.tap { |e| EditionContent.create!(work: other, edition: e) }
    assert_raises(EditionRemoval::Refused) { EditionRemoval.run(shared, work: other, move_to: @keep) }
    assert Edition.exists?(stranger.id)
  end
end
