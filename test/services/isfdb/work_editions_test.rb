require "test_helper"

module Isfdb
  class WorkEditionsTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    setup do
      @client = Client.new(base_url: BASE_URL)
      @work = Work.create!(title: "Crossfire", literary_form: "novel")
      @edition = Edition.create!(format: "hardcover")
      EditionContent.create!(work: @work, edition: @edition)
      EditionIdentifier.create!(edition: @edition, id_type: "isbn13", value: "9780765304674")
      EditionIdentifier.create!(edition: @edition, id_type: "isbn10", value: "0765304678")
    end

    def stub_editions(isbn, body)
      stub_request(:get, "#{BASE_URL}/isbn/#{isbn}/editions")
        .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    test "asks the adapter with the work's ISBN-13 first" do
      stub_editions("9780765304674", [ { title: "Crossfire", isbn_13: "9780765343895" } ])

      result = WorkEditions.for(@work, client: @client)

      assert_equal [ "9780765343895" ], result.map { |e| e["isbn_13"] }
    end

    test "falls through to the next ISBN when the first has no match" do
      stub_request(:get, "#{BASE_URL}/isbn/9780765304674/editions").to_return(status: 404)
      stub_editions("0765304678", [ { title: "Crossfire", isbn_13: "9780765343895" } ])

      result = WorkEditions.for(@work, client: @client)

      assert_equal [ "9780765343895" ], result.map { |e| e["isbn_13"] }
    end

    test "returns [] for a work with no ISBNs at all" do
      bare = Work.create!(title: "Untitled", literary_form: "novel")
      EditionContent.create!(work: bare, edition: Edition.create!)

      assert_equal [], WorkEditions.for(bare, client: @client)
    end
  end
end
