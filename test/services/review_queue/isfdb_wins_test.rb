require "test_helper"

module ReviewQueue
  class IsfdbWinsTest < ActiveSupport::TestCase
    def anchored_edition(**attrs)
      Edition.create!(**attrs).tap do |e|
        EditionContent.create!(work: Work.create!(title: "Book #{e.id}", literary_form: "novel"), edition: e)
        e.edition_identifiers.create!(id_type: "isfdb", value: "100#{e.id}")
      end
    end

    def isfdb(edition, fields) = EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {}, fields:)

    def conflict(edition, fields, source: "isfdb")
      PendingDecision.create!(kind: "enrichment_conflict", payload: { entity_type: "Edition", entity_id: edition.id, source:, fields: })
    end

    test "ISFDB's values win: the same-year date, the publisher, and the fills held up with them" do
      e = anchored_edition(publish_date: "1990", publisher: "Futura Orbit")
      isfdb(e, { "publish_date" => "1990-02", "publisher" => "Orbit", "page_count" => 412 })
      d = conflict(e, %w[publish_date publisher page_count])

      IsfdbWins.apply

      assert d.reload.accepted?
      assert_equal [ "1990-02", "Orbit", 412 ], [ e.reload.publish_date, e.publisher, e.page_count ]
      assert_equal "isfdb", e.field_sources["publisher"]
    end

    test "dates 2+ years apart, or a different format, stay pending as a printing question" do
      e1 = anchored_edition(publish_date: "1969", publisher: "NEL")
      isfdb(e1, { "publish_date" => "1979-11", "publisher" => "New English Library" })
      d1 = conflict(e1, %w[publish_date publisher])
      e2 = anchored_edition(publish_date: "2005", format: "paperback")
      isfdb(e2, { "publish_date" => "2005", "format" => "hardcover" })
      d2 = conflict(e2, %w[format])

      IsfdbWins.apply

      assert d1.reload.pending?
      assert_equal "ISFDB's printing is dated 1979; yours 1969", d1.payload["identity_question"]
      assert_equal "1969", e1.reload.publish_date
      assert_equal "ISFDB's printing is a hardcover; yours a paperback", d2.reload.payload["identity_question"]
    end

    test "a Goodreads conflict on an anchored edition is rejected; unanchored editions are left alone" do
      anchored = anchored_edition(publisher: "Orbit")
      EnrichmentRecord.create!(entity: anchored, provider: "goodreads", external_id: "9", fetched_at: Time.current, raw_payload: {}, fields: { "publisher" => "Futura" })
      goodreads = conflict(anchored, %w[publisher], source: "goodreads")
      loose = Edition.create!(publisher: "Pan")
      isfdb(loose, { "publisher" => "Pan Books" })
      unanchored = conflict(loose, %w[publisher])

      IsfdbWins.apply

      assert goodreads.reload.rejected?
      assert unanchored.reload.pending?
      assert_equal "Pan", loose.reload.publisher
    end

    test "plan is a dry run" do
      e = anchored_edition(publisher: "Futura Orbit")
      isfdb(e, { "publisher" => "Orbit" })
      d = conflict(e, %w[publisher])

      assert_equal [ :accept ], IsfdbWins.plan.map(&:action)
      assert d.reload.pending?
    end
  end
end
