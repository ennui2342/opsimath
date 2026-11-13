require "test_helper"

class KnownEditionsRefreshTest < ActiveSupport::TestCase
  # A provider double: returns the editions configured per ISBN, records calls.
  class FakeProvider
    WORK_ID_TYPE = "fake_work".freeze
    attr_reader :calls

    def initialize(error: nil, **by_isbn) = (@by_isbn = by_isbn; @error = error; @calls = [])
    def name = "isfdb" # uses isfdb's settings
    def capabilities = %i[known_editions]

    def known_editions(isbns:, work_ids: [])
      @calls << { isbns:, work_ids: }
      raise @error if @error

      isbn = isbns.find { |i| @by_isbn.key?(i) }
      work_id, editions = @by_isbn.fetch(isbn, [ nil, [] ])
      Providers::KnownEditions.new(work_ids: [ work_id ].compact, editions:)
    end
  end

  setup do
    @work = Work.create!(title: "Crossfire", literary_form: "novel")
    edition = Edition.create!(format: "hardcover")
    EditionContent.create!(work: @work, edition:)
    EditionIdentifier.create!(edition:, id_type: "isbn13", value: "9780765304674")
  end

  def ed(id, overrides = {})
    Providers::Edition.new({ provider: "isfdb", id:, publisher: "Tor", binding: "hc", isbn13: "9780765304674",
                             cover_url: "https://covers.test/#{id}.jpg" }.merge(overrides))
  end

  def refresh(provider, **) = KnownEditionsRefresh.new(provider:, refetch_before: nil, **).run

  test "stores the provider's editions and its id for the work, and when it asked" do
    provider = FakeProvider.new("9780765304674" => [ "1911", [ ed("1"), ed("2", binding: "pb", isbn13: "9780765343895") ] ])

    result = refresh(provider)

    assert_equal %w[1 2], @work.provider_editions.order(:provider_id).pluck(:provider_id)
    assert_equal [ [ "fake_work", "1911", "isbn_lookup" ] ], @work.work_identifiers.pluck(:id_type, :value, :source)
    assert_equal [ "9780765304674" ], ProviderEditionRefresh.find_by!(work: @work, provider: "isfdb").queried_isbns
    assert_equal 1, result.refreshed
  end

  test "a link pruned as a different work (TitleLinkPrune) isn't put back" do
    @work.work_identifiers.create!(id_type: "fake_work_rejected", value: "1911")
    provider = FakeProvider.new("9780765304674" => [ "1911", [ ed("1") ] ])

    refresh(provider)

    assert_not @work.work_identifiers.exists?(id_type: "fake_work")
  end

  test "the link comes from the edition's own printing: an omnibus edition is linked to the omnibus, not a novel in it" do
    edition = @work.editions.first
    EditionIdentifier.create!(edition:, id_type: "isfdb", value: "20507") # anchored: Mark's printing
    # The provider reports the novel's title for the ISBN (as isfdb-adapter
    # did before 2026-11-14); the anchored printing says it's the omnibus's.
    provider = FakeProvider.new("9780765304674" => [ "868", [ ed("20507", work_id: "11111"), ed("54237", work_id: "868", isbn13: "9780380701780") ] ])

    refresh(provider)

    assert_equal [ "11111" ], @work.work_identifiers.where(id_type: "fake_work").pluck(:value)
    assert_equal "11111", @work.provider_editions.find_by(provider_id: "20507").provider_work_id
  end

  test "an edition not yet anchored is linked by its ISBN's printing" do
    provider = FakeProvider.new("9780765304674" => [ "999", [ ed("1", work_id: "1911") ] ])

    refresh(provider)

    assert_equal [ "1911" ], @work.work_identifiers.where(id_type: "fake_work").pluck(:value)
  end

  test "a work the provider already identified is asked by its id next time" do
    @work.work_identifiers.create!(id_type: "fake_work", value: "1911")
    provider = FakeProvider.new

    refresh(provider)

    assert_equal [ "1911" ], provider.calls.sole[:work_ids]
  end

  test "keeps an edition's row id, updates it, drops what the provider no longer lists — never another provider's rows" do
    kept = @work.provider_editions.create!(provider: "isfdb", provider_id: "1", publisher: "Old")
    @work.provider_editions.create!(provider: "isfdb", provider_id: "99")
    other = @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL1M")

    refresh(FakeProvider.new("9780765304674" => [ "1911", [ ed("1") ] ]))

    assert_equal [ kept.id, other.id ].sort, @work.provider_editions.pluck(:id).sort
    assert_equal "Tor", kept.reload.publisher
  end

  test "skips a work fetched recently with unchanged ISBNs; re-asks when its ISBNs change" do
    ProviderEditionRefresh.create!(work: @work, provider: "isfdb", refreshed_at: 1.day.ago, queried_isbns: [ "9780765304674" ])
    @work.provider_editions.create!(provider: "isfdb", provider_id: "1") # found something: no title-fallback retry
    assert_equal 0, refresh(FakeProvider.new).due

    ProviderEditionRefresh.find_by(work: @work).update!(queried_isbns: [ "9999999999999" ])
    assert_equal 1, refresh(FakeProvider.new).due
  end

  test "due-ness is per provider" do
    ProviderEditionRefresh.create!(work: @work, provider: "openlibrary", refreshed_at: 1.hour.ago, queried_isbns: [ "9780765304674" ])

    assert_equal 1, refresh(FakeProvider.new).due # isfdb has never been asked
  end

  test "a provider failure leaves the work due" do
    result = refresh(FakeProvider.new(error: RuntimeError.new("down")))

    assert_equal 0, result.refreshed
    assert_not ProviderEditionRefresh.exists?(work: @work)
  end

  test "a work with no ISBN and no provider id is still asked, and marked as asked" do
    bare = Work.create!(title: "No ISBN", literary_form: "novel")
    provider = FakeProvider.new

    refresh(provider)

    assert_includes provider.calls, { isbns: [], work_ids: [] }
    assert ProviderEditionRefresh.exists?(work: bare, provider: "isfdb")
  end

  test "another provider's English ISBNs of the book help this one find it; translations and omnibuses don't" do
    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL1M", title: "Crossfire", isbn13: "9780000000011", language: "eng")
    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL2M", title: "Crossfire", isbn13: "9780000000022", language: "ger")
    @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL3M", title: "The Crossfire Omnibus", isbn13: "9780000000033", language: "eng")
    provider = FakeProvider.new

    refresh(provider)

    assert_equal [ "9780765304674", "9780000000011" ], provider.calls.find { |c| c[:isbns].include?("9780765304674") }[:isbns]
  end

  test "the migration carried ISFDB's step 2 timestamps over" do
    assert ProviderEditionRefresh.column_names.include?("queried_isbns")
    assert_not Work.column_names.include?("known_editions_refreshed_at")
  end

  test "a work found empty before the title fallback is asked again; one with editions isn't" do
    bare = Work.create!(title: "Found Nothing", literary_form: "novel")
    [ @work, bare ].each do |w|
      ProviderEditionRefresh.create!(work: w, provider: "isfdb", refreshed_at: KnownEditionsRefresh::TITLE_FALLBACK_SINCE - 1.hour,
                                     queried_isbns: w == @work ? [ "9780765304674" ] : [])
    end
    @work.provider_editions.create!(provider: "isfdb", provider_id: "1")
    provider = FakeProvider.new

    refresh(provider)

    assert_equal 1, provider.calls.size # only Found Nothing
    assert_equal [], provider.calls.sole[:isbns]
  end

  test "new printings are announced only when worth it: a new edition out, or a new cover for a wanted book" do
    @work.provider_editions.create!(provider: "isfdb", provider_id: "1", binding: "hc", publish_date: "2003")
    ProviderEditionRefresh.create!(work: @work, provider: "isfdb", refreshed_at: 1.year.ago, queried_isbns: [])
    recent = (Date.current.year).to_s
    provider = FakeProvider.new("9780765304674" => [ "1911", [ ed("1", binding: "hc", publish_date: "2003"),
                                                              ed("2", binding: "pb", publish_date: "1972"),          # old: silent
                                                              ed("3", binding: "pb", publish_date: recent),          # new edition out
                                                              ed("4", binding: "audio", publish_date: recent),       # not physical
                                                              ed("5", binding: "hc", publish_date: recent, publisher: "SFBC") ] ]) # book club

    refresh(provider)

    event = CatalogueEvent.find_by!(kind: "new_printings")
    assert_equal 1, event.details["count"]
    assert_match(/1 new printing in ISFDB \(Tor #{recent}\)/, event.summary)
  end

  test "printings fetched before refetch_before are fetched again" do
    work = Work.create!(title: "The Snow Queen", literary_form: "novel")
    ProviderEditionRefresh.create!(work:, provider: "isfdb", refreshed_at: 1.hour.ago, queried_isbns: [])
    ProviderEdition.create!(work:, provider: "isfdb", provider_id: "1")
    provider = Providers::Isfdb.new

    before = KnownEditionsRefresh.new(provider:, refetch_before: 2.hours.ago, deadline: 0.seconds).run.due
    assert_equal before + 1, KnownEditionsRefresh.new(provider:, refetch_before: Time.current, deadline: 0.seconds).run.due
  end
end
