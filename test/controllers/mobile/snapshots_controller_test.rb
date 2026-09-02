require "test_helper"

module Mobile
  class SnapshotsControllerTest < ActionDispatch::IntegrationTest
    setup do
      _token, @raw = ApiToken.issue!(user: users(:one), name: "mobile")
      @auth = { "Authorization" => "Bearer #{@raw}" }
    end

    def seed_snapshot
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work:, edition:)
      Copy.create!(edition:, disposition: "owned")
      MobileSnapshot.regenerate!
    end

    test "requires a valid bearer token" do
      get mobile_snapshot_version_url
      assert_response :unauthorized

      get mobile_snapshot_version_url, headers: { "Authorization" => "Bearer nope" }
      assert_response :unauthorized
    end

    test "version is 404 until a snapshot exists, then reports version/generated_at/bytes" do
      get mobile_snapshot_version_url, headers: @auth
      assert_response :not_found

      snapshot = seed_snapshot
      get mobile_snapshot_version_url, headers: @auth

      assert_response :success
      body = response.parsed_body
      assert_equal snapshot.version, body["version"]
      assert_equal snapshot.byte_size, body["bytes"]
      assert_equal snapshot.generated_at.iso8601, body["generated_at"]
    end

    test "show streams the sqlite file and supports conditional GET" do
      snapshot = seed_snapshot

      get mobile_snapshot_url, headers: @auth
      assert_response :success
      assert_equal "application/vnd.sqlite3", response.media_type
      assert_equal snapshot.byte_size, response.body.bytesize
      etag = response.headers["ETag"]
      assert etag.present?

      get mobile_snapshot_url, headers: @auth.merge("If-None-Match" => etag)
      assert_response :not_modified
    end
  end
end
