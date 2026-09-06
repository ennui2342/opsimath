require "test_helper"

module Settings
  class AuthoritiesControllerTest < ActionDispatch::IntegrationTest
    setup { sign_in_as users(:one); Notifications.notifiers = [] }
    teardown { Notifications.notifiers = nil }

    test "index lists the registered vocabularies" do
      get settings_authorities_url
      assert_response :success
      assert_select "a", text: /Publishers/
    end

    test "show renders a vocabulary's authority file with usage counts" do
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Tor.com")
      term.register_variant("Tordotcom")
      Edition.create!(publisher: "Tordotcom")

      get settings_authority_url("publisher")

      assert_response :success
      assert_select "*", text: /Tor\.com/
      assert_select "*", text: /Tordotcom/
    end

    test "show 404s an unknown vocabulary" do
      get settings_authority_url("weather")
      assert_response :not_found
    end

    test "rescan runs the sweep and reports" do
      post settings_authority_rescan_url("publisher")
      assert_redirected_to settings_authority_path("publisher")
    end

    test "/settings redirects into authorities" do
      get "/settings"
      assert_redirected_to "/settings/authorities"
    end
  end
end
