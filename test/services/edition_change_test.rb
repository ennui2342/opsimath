require "test_helper"

class EditionChangeTest < ActiveSupport::TestCase
  setup do
    stub_request(:get, %r{https://covers\.test/.*}).to_return(status: 200, body: File.binread(Rails.root.join("test/fixtures/files/cover.png")),
                                                             headers: { "Content-Type" => "image/png" })
    @work = Work.create!(title: "The Anubis Gates", literary_form: "novel")
    @edition = Edition.create!(publisher: "HarperCollins", publish_date: "1993", format: "paperback", page_count: 400, cover_artist: "Someone",
                               field_sources: { "publisher" => "isfdb", "publish_date" => "isfdb", "notes" => "manual" })
    EditionContent.create!(work: @work, edition: @edition)
    @edition.cover_image.attach(io: StringIO.new("old"), filename: "old.jpg", content_type: "image/jpeg")
    { "isbn13" => Isbn.to_13("0586065504"), "isbn10" => "0586065504", "isfdb" => "111", "goodreads" => "42" }
      .each { |type, value| @edition.edition_identifiers.create!(id_type: type, value:) }
    @edition.enrichment_records.create!(provider: "isfdb", external_id: "111", fetched_at: Time.current, raw_payload: {}, fields: { "publisher" => "HarperCollins" })
    @copy = Copy.create!(edition: @edition, disposition: "owned")
    @reading = Reading.create!(work: @work, edition: @edition, copy: @copy, status: "completed", source: "owned_copy", date_finished: Date.new(2020, 1, 1))
    @card = [ { "provider" => "isfdb", "id" => "222", "publisher" => "Triad Grafton", "publish_date" => "1986", "binding" => "pb",
                "isbn10" => "0586065504", "cover_url" => "https://covers.test/222.png", "cover_artist" => "Tim White" } ]
  end

  test "the edition becomes the chosen printing wholesale; copies, readings and Goodreads provenance stay" do
    EditionChange.run(@edition, @card)
    @edition.reload

    assert_equal [ "Triad Grafton", "1986", "paperback", "mass_market", nil, "Tim White" ],
                 [ @edition.publisher, @edition.publish_date, @edition.format, @edition.format_detail, @edition.page_count, @edition.cover_artist ]
    assert_equal "222.png", @edition.cover_image.filename.to_s
    assert_equal "isfdb", @edition.field_sources["cover_image"]
    assert_equal "manual", @edition.field_sources["notes"]
    assert_equal({ "isbn13" => Isbn.to_13("0586065504"), "isbn10" => "0586065504", "isfdb" => "222", "goodreads" => "42" },
                 @edition.edition_identifiers.pluck(:id_type, :value).to_h)
    assert_equal [ "222" ], @edition.enrichment_records.pluck(:external_id)
    assert_equal [ @copy ], @edition.copies.to_a
    assert_equal @edition, @reading.reload.edition
  end

  test "a printing with no cover leaves the edition without one rather than keeping the old printing's" do
    @card.first.delete("cover_url")

    EditionChange.run(@edition, @card)

    assert_not @edition.reload.cover_image.attached?
  end

  test "settles the queued printing choice and moots provider conflicts, leaving others" do
    choice = PendingDecision.create!(kind: "enrichment_printing_choice", payload: { entity_type: "Edition", entity_id: @edition.id, source: "isfdb", candidates: [] })
    conflict = PendingDecision.create!(kind: "enrichment_conflict", payload: { entity_type: "Edition", entity_id: @edition.id, source: "isfdb", fields: [ "publisher" ] })
    goodreads = PendingDecision.create!(kind: "enrichment_conflict", payload: { entity_type: "Edition", entity_id: @edition.id, source: "goodreads", fields: [ "publisher" ] })
    other = PendingDecision.create!(kind: "enrichment_printing_choice", payload: { entity_type: "Edition", entity_id: @edition.id + 1, source: "isfdb", candidates: [] })

    EditionChange.run(@edition, @card)

    assert_equal %w[accepted rejected pending pending], [ choice, conflict, goodreads, other ].map { |d| d.reload.status }
    assert choice.resolved_at
  end
end
