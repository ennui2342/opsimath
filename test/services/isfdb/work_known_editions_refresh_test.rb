require "test_helper"

module Isfdb
  class WorkKnownEditionsRefreshTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup do
      @client = Client.new(base_url: BASE_URL)
      @work = Work.create!(title: "Crossfire", literary_form: "novel")
      @edition = Edition.create!(format: "hardcover")
      EditionContent.create!(work: @work, edition: @edition)
      EditionIdentifier.create!(edition: @edition, id_type: "isbn13", value: "9780765304674")
    end

    def stub_editions(isbn, body, status: 200)
      stub_request(:get, "#{BASE_URL}/isbn/#{isbn}/editions")
        .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def edition(pub_id, overrides = {})
      { "_isfdb_pub_id" => pub_id, "_isfdb_title_id" => 1911, "binding" => "hc", "publisher" => "Tor",
        "publish_date" => "2003-12", "isbn_13" => "9780765304674", "isbn_10" => "", "title" => "Crossfire",
        "cover_url" => "https://covers.test/#{pub_id}.jpg|https://mirror.test/#{pub_id}.jpg", "cover_artists" => [ "John Harris" ] }.merge(overrides)
    end

    test "caches every edition ISFDB knows for the work, ebooks included, and its title id" do
      stub_editions("9780765304674", [
        edition(1),
        edition(2, "binding" => "pb", "isbn_13" => "9780765343895", "publish_date" => "2004-11"),
        edition(3, "binding" => "ebook", "isbn_13" => "", "isbn_10" => "0812564022")
      ])

      result = WorkKnownEditionsRefresh.run(client: @client)

      eds = @work.provider_editions.order(:provider_id)
      assert_equal %w[1 2 3], eds.map(&:provider_id)
      assert_equal %w[hc pb ebook], eds.map(&:binding)
      assert_equal "https://covers.test/1.jpg", eds.first.cover_url
      assert_equal "John Harris", eds.first.cover_artist
      assert_equal [ "9780765304674", "9780765343895", Isbn.to_13("0812564022") ], eds.map(&:isbn)
      assert_equal [ [ "isfdb_title", "1911", "isbn_lookup" ] ], @work.work_identifiers.pluck(:id_type, :value, :source)
      assert_equal [ "9780765304674" ], @work.reload.known_editions_queried_isbns
      assert_equal 1, result.refreshed
    end

    test "the title id comes from the work's own printings, not from omnibuses that contain it" do
    stub_editions("9780765304674", [
      edition(1),
      edition(2, "isbn_13" => "9780000000002", "_isfdb_title_id" => 5555, "title" => "A Three-in-One Omnibus")
    ])

    WorkKnownEditionsRefresh.run(client: @client)

    assert_equal [ "1911" ], @work.work_identifiers.pluck(:value)
    assert_equal 2, @work.provider_editions.count # the omnibus is still a known edition
  end

  test "covers every catalogued work, owned or not" do
      stub_editions("9780765304674", [ edition(1) ])

      WorkKnownEditionsRefresh.run(client: @client) # no Copy at all

      assert_equal 1, @work.provider_editions.count
    end

    test "a refresh keeps an edition's row id, updates it, and drops editions ISFDB no longer lists" do
      kept = @work.provider_editions.create!(provider: "isfdb", provider_id: "1", publisher: "Old")
      @work.provider_editions.create!(provider: "isfdb", provider_id: "99")
      other = @work.provider_editions.create!(provider: "openlibrary", provider_id: "OL1M")
      stub_editions("9780765304674", [ edition(1) ])

      WorkKnownEditionsRefresh.run(client: @client)

      assert_equal [ kept.id, other.id ].sort, @work.provider_editions.pluck(:id).sort # other providers untouched
      assert_equal "Tor", kept.reload.publisher
    end

    test "skips a work refreshed recently with unchanged ISBNs" do
      @work.update_columns(known_editions_refreshed_at: 1.day.ago, known_editions_queried_isbns: [ "9780765304674" ])

      result = WorkKnownEditionsRefresh.run(client: @client) # no stubs — a request would raise

      assert_equal 0, result.stale
    end

    test "re-queries a work whose ISBNs changed" do
      @work.update_columns(known_editions_refreshed_at: 1.hour.ago, known_editions_queried_isbns: [ "9999999999999" ])
      stub_editions("9780765304674", [ edition(1) ])

      WorkKnownEditionsRefresh.run(client: @client)

      assert_equal 1, @work.provider_editions.count
    end

    test "two works can share a title id — an omnibus resolves to a novel inside it" do
      omnibus = Work.create!(title: "Peace and War", literary_form: "novel")
      ed = Edition.create!(format: "paperback")
      EditionContent.create!(work: omnibus, edition: ed)
      EditionIdentifier.create!(edition: ed, id_type: "isbn13", value: "9780575078710")
      stub_editions("9780765304674", [ edition(1) ])
      stub_editions("9780575078710", [ edition(7, "isbn_13" => "9780575078710", "title" => "Peace and War") ])

      WorkKnownEditionsRefresh.run(client: @client)

      assert_equal 2, WorkIdentifier.where(id_type: "isfdb_title", value: "1911").count
    end

    test "an adapter error leaves the work stale for the next run" do
      stub_editions("9780765304674", {}, status: 503)

      result = WorkKnownEditionsRefresh.run(client: @client)

      assert_equal 0, result.refreshed
      assert_nil @work.reload.known_editions_refreshed_at
    end
  end
end
