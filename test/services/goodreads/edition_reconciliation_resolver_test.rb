require "test_helper"

module Goodreads
  class EditionReconciliationResolverTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"
    READ_DATE = Date.new(2020, 1, 1)

    setup do
      @isfdb = Isfdb::Client.new(base_url: BASE_URL)
      # a book I own in one edition, read once
      @work = Work.create!(title: "Facets", literary_form: "novel")
      WorkContributor.create!(work: @work, contributor: Contributor.create!(name: "Walter Jon Williams"), role: "author")
      @old_edition = Edition.create!(format: "paperback", publisher: "Grafton")
      EditionContent.create!(work: @work, edition: @old_edition)
      EditionIdentifier.create!(edition: @old_edition, id_type: "goodreads", value: "3945054")
      EditionIdentifier.create!(edition: @old_edition, id_type: "isbn10", value: "0586213872")
      @old_copy = Copy.create!(edition: @old_edition, disposition: "owned")
      @old_reading = Reading.create!(work: @work, edition: @old_edition, status: "completed",
                                     source: "owned_copy", date_finished: READ_DATE)

      # the feed row that re-shelved to a different Goodreads edition of
      # the same read (the read date carries over, per Goodreads behaviour)
      @rec = EditionReconciliation.create!(work: @work, payload: {
        "goodreads_book_id" => "1343099", "shelf" => "read", "work_id" => @work.id,
        "candidate_edition_ids" => [ @old_edition.id ],
        "feed_item" => {
          "goodreads_book_id" => "1343099", "title" => "Facets", "author_name" => "Walter Jon Williams",
          "isbn" => "0812564022", "book_image_url" => nil, "user_read_at" => READ_DATE.iso8601
        }
      })

      stub_request(:get, /#{Regexp.escape(BASE_URL)}\/isbn\/.+/).to_return(status: 404)
    end

    def resolve(**kwargs) = EditionReconciliationResolver.resolve(@rec, isfdb: @isfdb, **kwargs)

    test "relink adds the new goodreads id to the chosen edition; the existing reading is re-touched in place" do
      resolve(resolution: "relink", target_edition_id: @old_edition.id)

      assert @old_edition.edition_identifiers.exists?(id_type: "goodreads", value: "1343099")
      assert_equal [ @old_reading ], @work.reload.readings.to_a
      assert_equal @old_edition, @old_reading.reload.edition
      assert @rec.reload.resolved?
      assert @rec.resolution_relink?
    end

    test "change_edition retires the old copy and builds+enriches a new owned edition" do
      resolve(resolution: "change_edition", target_edition_id: @old_edition.id)

      assert_equal "replaced", @old_copy.reload.disposition
      new_edition = @rec.reload.resolved_edition
      assert_not_equal @old_edition, new_edition
      assert new_edition.edition_identifiers.exists?(id_type: "goodreads", value: "1343099")
      assert_equal 1, new_edition.copies.owned.count

      # the historical reading stays on the edition it happened in; the
      # new edition is just an owned copy, unread
      assert_equal @old_edition, @old_reading.reload.edition
      assert_empty new_edition.readings
    end

    test "add_edition keeps the old copy owned and adds a second owned edition" do
      resolve(resolution: "add_edition")

      assert_equal "owned", @old_copy.reload.disposition
      assert_equal 2, @work.reload.editions.count
      assert_equal 1, @rec.reload.resolved_edition.copies.owned.count
      assert_empty @rec.resolved_edition.readings
    end

    test "add_edition with a new read date opens a reading on the new edition (a reread in the new copy)" do
      @rec.update!(payload: @rec.payload.deep_merge("feed_item" => { "user_read_at" => "2024-08-01" }))

      resolve(resolution: "add_edition")

      new_edition = @rec.reload.resolved_edition
      assert_equal @old_edition, @old_reading.reload.edition
      assert_equal Date.new(2024, 8, 1), new_edition.readings.sole.date_finished
    end

    test "unowned_read builds a Copy-less edition and logs the read against it with the chosen source" do
      resolve(resolution: "unowned_read", source: "library")

      new_edition = @rec.reload.resolved_edition
      assert_empty new_edition.copies
      reading = new_edition.readings.sole
      assert_equal "library", reading.source
      assert_equal "completed", reading.status
      assert_equal READ_DATE, reading.date_finished
      assert_equal @old_edition, @old_reading.reload.edition # untouched
    end

    test "unowned_read rejects an unknown source" do
      assert_raises(EditionReconciliationResolver::InvalidResolution) do
        resolve(resolution: "unowned_read", source: "pirated")
      end
    end

    test "rejected marks it resolved and changes nothing" do
      resolve(resolution: "rejected")

      assert @rec.reload.resolved?
      assert @rec.resolution_rejected?
      assert_equal [ @old_reading ], @work.reload.readings.to_a
      assert_equal 1, @work.editions.count
    end

    test "relink without a target is rejected" do
      assert_raises(EditionReconciliationResolver::InvalidResolution) { resolve(resolution: "relink") }
    end
  end
end
