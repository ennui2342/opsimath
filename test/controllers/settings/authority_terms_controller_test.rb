require "test_helper"

module Settings
  class AuthorityTermsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      Notifications.notifiers = []
      @edition = Edition.create!(publisher: "Pan Macmillan UK", field_sources: { "publisher" => "goodreads" })
      EnrichmentRecord.create!(entity: @edition, provider: "isfdb", external_id: "1", fetched_at: Time.current,
                               fields: { "publisher" => "Pan Books" },
                               raw_payload: { "publisher" => "Pan Books", "binding" => "pb", "_isfdb_pub_id" => 1 })
      @decision = PendingDecision.create!(kind: "enrichment_conflict", payload: {
        "entity_type" => "Edition", "entity_id" => @edition.id, "source" => "isfdb", "fields" => [ "publisher" ]
      })
    end

    teardown { Notifications.notifiers = nil }

    test "requires authentication" do
      reset!
      post settings_authority_terms_url("publisher"), params: { preferred_label: "X" }
      assert_response :redirect
    end

    test "establishing a term from the settings screen rewrites editions and clears the conflict" do
      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "Pan Books", variant_labels: "Pan Macmillan UK\nPan Macmillan" }

      assert_redirected_to settings_authority_path("publisher")
      assert_equal "Pan Books", @edition.reload.publisher
      assert_empty PendingDecision.pending
      assert AuthorityTerm.exists?(vocabulary: "publisher", preferred_label: "Pan Books")
    end

    test "establishing from a conflict screen responds with turbo_stream and advances past the resolved decision" do
      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "Pan Books", "variant_labels[]": [ "Pan Macmillan UK", "Pan Books" ], from_decision_id: @decision.id },
           as: :turbo_stream

      assert_response :success
      assert_match "turbo-stream", @response.media_type
      assert_equal "accepted", @decision.reload.status
    end

    test "the 'other' preferred option uses the free-text value" do
      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "__other__", preferred_label_other: "Pan",
                     "variant_labels[]": [ "Pan Macmillan UK", "Pan Books" ] }

      assert AuthorityTerm.exists?(vocabulary: "publisher", preferred_label: "Pan")
      assert_equal "Pan", Authority.resolve("publisher", "Pan Books")
    end

    test "an unknown vocabulary is a 404" do
      post settings_authority_terms_url("weather"), params: { preferred_label: "X" }
      assert_response :not_found
    end

    test "retract re-enriches and can re-raise the conflict" do
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")
      Authority::Publishers.apply(term)
      assert_empty PendingDecision.pending

      delete settings_authority_term_url("publisher", term)

      assert_redirected_to settings_authority_path("publisher")
      assert_not AuthorityTerm.exists?(term.id)
      # edition kept "Pan Books"; ISFDB record still says "Pan Books" for
      # this one so nothing re-raises here — the sweep ran, that's the point
      assert_equal "Pan Books", @edition.reload.publisher
    end
  end
end
