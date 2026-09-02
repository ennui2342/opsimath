require "test_helper"

module Isfdb
  class SiblingIsbnRefreshTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup do
      @client = Client.new(base_url: BASE_URL)
      @work = Work.create!(title: "Crossfire", literary_form: "novel")
      @edition = Edition.create!(format: "hardcover")
      EditionContent.create!(work: @work, edition: @edition)
      EditionIdentifier.create!(edition: @edition, id_type: "isbn13", value: "9780765304674")
      Copy.create!(edition: @edition, disposition: "owned")
    end

    def stub_editions(isbn, body)
      stub_request(:get, "#{BASE_URL}/isbn/#{isbn}/editions")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    test "caches the sibling ISBN-13s for an owned work" do
      stub_editions("9780765304674", [
        { isbn_13: "9780765304674", binding: "hc" },
        { isbn_13: "9780765343895", binding: "pb" },
        { isbn_10: "0812564022", binding: "pb" }
      ])

      result = SiblingIsbnRefresh.run(client: @client)

      row = WorkSiblingIsbns.find(@work.id)
      assert_equal %w[9780765304674 9780765343895], row.isbn13s.first(2)
      assert_includes row.isbn13s, Isbn.to_13("0812564022")
      assert_equal [ "9780765304674" ], row.queried_isbns
      assert_equal 1, result.refreshed
      assert_not result.truncated
    end

    test "skips a work whose cache row is still fresh and unchanged" do
      WorkSiblingIsbns.create!(work_id: @work.id, isbn13s: %w[9780765304674],
                               queried_isbns: %w[9780765304674], refreshed_at: 1.day.ago)

      result = SiblingIsbnRefresh.run(client: @client) # no stubs — a request would raise

      assert_equal 0, result.stale
    end

    test "re-queries a work that gained an ISBN" do
      WorkSiblingIsbns.create!(work_id: @work.id, isbn13s: [],
                               queried_isbns: %w[9999999999999], refreshed_at: 1.hour.ago)
      stub_editions("9780765304674", [ { isbn_13: "9780765343895" } ])

      SiblingIsbnRefresh.run(client: @client)

      assert_equal %w[9780765343895], WorkSiblingIsbns.find(@work.id).isbn13s
    end

    test "prunes cache rows for works no longer owned" do
      WorkSiblingIsbns.create!(work_id: 999_999, isbn13s: %w[x], queried_isbns: %w[x], refreshed_at: Time.current)
      stub_editions("9780765304674", [])

      SiblingIsbnRefresh.run(client: @client)

      assert_not WorkSiblingIsbns.exists?(work_id: 999_999)
    end

    test "an adapter error for one work is swallowed, others still cache" do
      stub_request(:get, "#{BASE_URL}/isbn/9780765304674/editions").to_return(status: 503)

      result = SiblingIsbnRefresh.run(client: @client)

      assert_equal 0, result.refreshed
      assert_not WorkSiblingIsbns.exists?(work_id: @work.id)
    end
  end
end
