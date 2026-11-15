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
  end
end
