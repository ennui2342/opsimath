require "test_helper"

class KnownEditionsRefreshTest < ActiveSupport::TestCase
  # A provider double: returns the editions configured per ISBN, records calls.
  class FakeProvider
    WORK_ID_TYPE = "fake_work".freeze
    attr_reader :calls

    def initialize(error: nil, **by_isbn) = (@by_isbn = by_isbn; @error = error; @calls = [])
    def name = "isfdb" # uses isfdb's settings
    def capabilities = %i[known_editions]

    def known_editions(isbns:, work_ids: [], title: nil, author: nil)
      @calls << { isbns:, work_ids:, title: }
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

  def refresh(provider) = KnownEditionsRefresh.new(provider:).run

  test "stores the provider's editions and its id for the work, and when it asked" do
    provider = FakeProvider.new("9780765304674" => [ "1911", [ ed("1"), ed("2", binding: "pb", isbn13: "9780765343895") ] ])

    result = refresh(provider)

    assert_equal %w[1 2], @work.provider_editions.order(:provider_id).pluck(:provider_id)
    assert_equal [ [ "fake_work", "1911", "isbn_lookup" ] ], @work.work_identifiers.pluck(:id_type, :value, :source)
    assert_equal [ "9780765304674" ], ProviderEditionRefresh.find_by!(work: @work, provider: "isfdb").queried_isbns
    assert_equal 1, result.refreshed
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

  test "a work with no ISBN and no provider id is still asked — by its title, for the provider to search" do
    bare = Work.create!(title: "No ISBN", literary_form: "novel")
    provider = FakeProvider.new

    refresh(provider)

    assert_includes provider.calls, { isbns: [], work_ids: [], title: "No ISBN" }
    assert ProviderEditionRefresh.exists?(work: bare, provider: "isfdb")
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

    assert_equal [ "Found Nothing" ], provider.calls.map { |c| c[:title] }
  end
end
