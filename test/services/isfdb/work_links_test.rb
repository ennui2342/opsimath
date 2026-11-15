require "test_helper"

module Isfdb
  class WorkLinksTest < ActiveSupport::TestCase
    ISFDB = ENV.fetch("ISFDB_ADAPTER_URL")

    def title(id, name, type, main: id)
      stub_request(:get, "#{ISFDB}/titles/#{id}").to_return(status: 200, body: {
        id:, title: name, type:, variants: [], main: { id: main, title: name, type:, year: 1994, language: "eng", authors: [], author_aliases: [] }
      }.to_json)
    end

    test "an edition's publication of a variant title record leaves the work's link to the main one alone" do
      title(1500, "Ubik", "NOVEL")
      title(1501, "Ubik", "NOVEL", main: 1500) # a reissue's variant
      work = work_with_edition("Ubik", links: [ [ 1500, "isbn_lookup" ] ], anchor: 7, printings: { 7 => [ 1501, "Ubik" ] })

      assert_nil WorkLinks.sync(work)
      assert_equal [ "1500" ], work.reload.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
    end

    def work_with_edition(name, links: [], anchor: nil, printings: {}, isbn: nil)
      work = Work.create!(title: name, literary_form: "novel", field_sources: { "title" => "isfdb" })
      links.each { |id, source| work.work_identifiers.create!(id_type: "isfdb_title", value: id.to_s, source:) }
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      edition.edition_identifiers.create!(id_type: "isfdb", value: anchor.to_s) if anchor
      edition.edition_identifiers.create!(id_type: "isbn13", value: isbn) if isbn
      printings.each { |pub, (title_id, ttl, pisbn)| ProviderEdition.create!(work:, provider: "isfdb", provider_id: pub.to_s, title: ttl, provider_work_id: title_id&.to_s, isbn13: pisbn) }
      work
    end

    test "an omnibus edition's work takes the omnibus's title in place of a novel's, and its type follows at once" do
      title(29436, "Live Robots", "OMNIBUS")
      title(868, "Wetware", "NOVEL")
      work = work_with_edition("Live Robots", links: [ [ 868, "isbn_lookup" ] ], anchor: 20507, printings: { 20507 => [ 29436, "Live Robots" ] })

      change = WorkLinks.sync(work)

      assert_equal [ "868" ], change.drop.map(&:first)
      work.reload
      assert_equal [ "29436" ], work.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
      assert_equal "omnibus", work.literary_form
    end

    test "a link Mark made stays; a work with nothing to go on is left alone" do
      title(55, "A Dance with Dragons", "NOVEL")
      split = work_with_edition("A Dance with Dragons 1", links: [ [ 867793, "manual" ] ], isbn: "9780007466061")
      assert_nil WorkLinks.sync(split)

      unfetched = work_with_edition("Unfetched", links: [ [ 9, "isbn_lookup" ] ], anchor: 1, printings: { 1 => [ nil, "Unfetched" ] })
      assert_nil WorkLinks.sync(unfetched)

      wanted = Work.create!(title: "Wanted", literary_form: "novel")
      wanted.work_identifiers.create!(id_type: "isfdb_title", value: "7")
      assert_nil WorkLinks.sync(wanted)
    end

    test "an edition not yet anchored goes by its ISBN's printings, less a title rejected for the work" do
      title(1911, "The Forever War", "NOVEL")
      title(5000, "Peace and War", "OMNIBUS")
      work = work_with_edition("The Forever War", isbn: "9780860078821",
                                                  printings: { 1 => [ 1911, "The Forever War", "9780860078821" ], 2 => [ 5000, "Peace and War", "9780860078821" ] })
      work.work_identifiers.create!(id_type: "isfdb_title_rejected", value: "5000")

      WorkLinks.sync(work)

      assert_equal [ "1911" ], work.reload.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
    end
  test "relinked to another title record, the work takes its authors too" do
      stub_request(:get, "#{ISFDB}/titles/36323").to_return(status: 200, body: {
        id: 36323, title: "New Worlds Quarterly 4", type: "ANTHOLOGY", variants: [],
        main: { id: 36323, title: "New Worlds Quarterly 4", type: "ANTHOLOGY", year: 1972, language: "eng",
                authors: [ { id: "34", name: "Michael Moorcock" } ], author_aliases: [] }
      }.to_json)
      title(33373, "New Worlds 4", "ANTHOLOGY")
      work = work_with_edition("New Worlds 4", links: [ [ 33373, "isbn_lookup" ] ], anchor: 5, printings: { 5 => [ 36323, "New Worlds Quarterly 4" ] })
      work.work_contributors.create!(contributor: Contributor.create!(name: "David Garnett"), role: "author")
      work.work_contributors.create!(contributor: Contributor.create!(name: "Michael Moorcock"), role: "contributor")

      WorkLinks.sync(work)

      roles = work.reload.work_contributors.includes(:contributor).to_h { |wc| [ wc.contributor.name, wc.role ] }
      assert_equal({ "David Garnett" => "contributor", "Michael Moorcock" => "author" }, roles)
    end
  test "relinked from a printing chosen in a search: leaves the old record's ISFDB series, keeps the new one's number" do
      title(36323, "New Worlds Quarterly 4", "ANTHOLOGY")
      title(33373, "New Worlds 4", "ANTHOLOGY")
      work = work_with_edition("New Worlds 4", links: [ [ 33373, "isbn_lookup" ] ], anchor: 23811)
      edition = work.editions.first
      EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "23811", fetched_at: Time.current, fields: {},
                               raw_payload: { "work_id" => "36323" })
      ProviderEdition.create!(work:, provider: "isfdb", provider_id: "1", title: "New Worlds Quarterly 4", provider_work_id: "36323",
                              series_id: 24354, series_name: "New Worlds Quarterly", series_num: 4)
      garnett = WorkSeries.create!(work:, series: Series.create!(name: "New Worlds (Garnett)", isfdb_series_id: 8228), position: 4)
      quarterly = WorkSeries.create!(work:, series: Series.create!(name: "New Worlds Quarterly", isfdb_series_id: 24354), position: 4)

      WorkLinks.sync(work)

      assert_equal [ "36323" ], work.reload.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
      assert_not WorkSeries.exists?(garnett.id)
      assert_equal 4, quarterly.reload.position
    end

    test "a relinked omnibus stays in an ISFDB series its printings don't name, without a number" do
      title(500, "The Book of Morgaine", "OMNIBUS")
      title(501, "Gate of Ivrel", "NOVEL")
      work = work_with_edition("The Book of Morgaine", links: [ [ 501, "isbn_lookup" ] ], anchor: 9001)
      work.update!(literary_form: "omnibus")
      ProviderEdition.create!(work:, provider: "isfdb", provider_id: "9001", title: "The Book of Morgaine", provider_work_id: "500")
      filing = WorkSeries.create!(work:, series: Series.create!(name: "Morgaine", isfdb_series_id: 77), position: 1)

      WorkLinks.sync(work)

      assert WorkSeries.exists?(filing.id)
      assert_nil filing.reload.position
    end

    test "an omnibus has no number in a series its printings don't number, relinked or not" do
      work = Work.create!(title: "1Q84", literary_form: "omnibus")
      filing = WorkSeries.create!(work:, series: Series.create!(name: "1Q84"), position: 3)

      WorkLinks.sync(work)

      assert_nil filing.reload.position
    end
  end
end
