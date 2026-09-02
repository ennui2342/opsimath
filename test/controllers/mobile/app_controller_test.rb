require "test_helper"

module Mobile
  class AppControllerTest < ActionDispatch::IntegrationTest
    test "the shell requires a session" do
      get mobile_app_url
      assert_redirected_to new_session_path
    end

    test "the shell renders standalone with an injected token and snapshot URLs" do
      sign_in_as users(:one)
      get mobile_app_url

      assert_response :success
      assert_no_match(/<nav|opsimath web layout/, response.body) # not the app layout
      assert_match %r{window\.__pocket = \{.*"apiToken":".+?".*\}}, response.body
      assert_includes response.body, mobile_snapshot_version_path
      assert_match %r{/assets/sqljs-\w+\.js}, response.body
      assert_match %r{<link rel="manifest"}, response.body
      assert_match %r{<div id="scanner" hidden>.*<video id="cam"}m, response.body # barcode scanner overlay
    end

    test "the first load issues a token, later loads reuse it, ?reset rotates it" do
      user = users(:one)
      sign_in_as user

      get mobile_app_url
      issued = response.body[/"apiToken":"([^"]+)"/, 1]
      assert issued.present?
      assert ApiToken.authenticate(issued)

      get mobile_app_url
      assert_match(/"apiToken":null/, response.body) # not rotated — client keeps what it has
      assert ApiToken.authenticate(issued)

      get mobile_app_url(reset: 1)
      rotated = response.body[/"apiToken":"([^"]+)"/, 1]
      assert_not_equal issued, rotated
      assert_nil ApiToken.authenticate(issued)
      assert_equal 1, user.api_tokens.where(name: "mobile-pwa").count
    end

    test "manifest is public JSON with the right scope" do
      get mobile_manifest_url
      assert_response :success
      assert_equal "application/manifest+json", response.media_type
      manifest = JSON.parse(response.body)
      assert_equal mobile_app_path, manifest["start_url"]
      assert_equal "standalone", manifest["display"]
    end

    test "service worker is public JS that precaches the shell" do
      get mobile_service_worker_url
      assert_response :success
      assert_equal "text/javascript", response.media_type
      assert_match(/const CACHE = "pocket-[0-9a-f]{12}"/, response.body)
      assert_includes response.body, "/mobile/snapshot" # the skip rule
      assert_match %r{/assets/sqljs-\w+\.wasm}, response.body
    end
  end
end
