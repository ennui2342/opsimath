require "test_helper"

module Settings
  class AuthorityTermsControllerTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as users(:one)
      Notifications.notifiers = []
      @edition = Edition.create!(publisher: "Pan Macmillan UK", field_sources: { "publisher" => "goodreads" })
      EnrichmentRecord.create!(entity: @edition, provider: "goodreads", external_id: "g", fetched_at: 1.day.ago,
                               fields: { "publisher" => "Pan Macmillan UK" }, raw_payload: { "publisher" => "Pan Macmillan UK" })
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

    test "the settings screen sends you to a preview first, and confirming establishes" do
      # no confirm -> preview
      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "Pan Books", variant_labels: "Pan Macmillan UK\nPan Macmillan" }
      assert_response :redirect
      assert_match "/terms/preview", @response.redirect_url
      assert_not AuthorityTerm.exists?(vocabulary: "publisher")

      # confirm -> established
      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "Pan Books", "variant_labels[]": [ "Pan Macmillan UK", "Pan Macmillan" ], confirm: "1" }

      assert_redirected_to settings_authority_path("publisher")
      assert_equal "Pan Books", @edition.reload.publisher
      assert_empty PendingDecision.pending
      assert AuthorityTerm.exists?(vocabulary: "publisher", preferred_label: "Pan Books")
    end

    test "preview classifies the affected editions by whether ISFDB corroborates the rewrite" do
      get settings_authority_terms_preview_url("publisher"),
          params: { preferred_label: "Pan Books", variant_labels: [ "Pan Macmillan UK" ] }, as: :json

      body = JSON.parse(@response.body)
      assert_equal 1, body["rewritten"]      # @edition, currently "Pan Macmillan UK"
      assert_equal 1, body["corroborated"]   # its ISFDB record says "Pan Books"
      assert_equal 0, body["unmatched"]
      assert_not body["risky"]
    end

    test "preview renders the HTML confirm page with the edition table" do
      # a contradicted row so the risky banner and the ⚠ branch both render
      other = Edition.create!(publisher: "Pan Macmillan UK", field_sources: { "publisher" => "goodreads" })
      Work.create!(title: "Some Novel", literary_form: "novel").tap { |w| EditionContent.create!(work: w, edition: other) }
      EnrichmentRecord.create!(entity: other, provider: "isfdb", external_id: "9", fetched_at: Time.current,
                               fields: { "publisher" => "Orbit" }, raw_payload: {})

      get settings_authority_terms_preview_url("publisher"),
          params: { preferred_label: "Pan Books", variant_labels: [ "Pan Macmillan UK" ] }

      assert_response :success
      assert_select "h1", /Establish/
      assert_select "table tbody tr", 2
      assert_select "p", /Check the flagged rows/
    end

    test "establishing from a conflict screen responds with turbo_stream and advances past the resolved decision" do
      # a second, unrelated conflict so the turbo response has to render a
      # real _decision_comparison from this controller's view context
      other = Edition.create!(publisher: "Wrong", field_sources: { "publisher" => "goodreads" })
      Work.create!(title: "Another Book", literary_form: "novel").tap { |w| EditionContent.create!(work: w, edition: other) }
      EnrichmentRecord.create!(entity: other, provider: "isfdb", external_id: "2", fetched_at: Time.current,
                               fields: { "publisher" => "Also Wrong" }, raw_payload: {})
      PendingDecision.create!(kind: "enrichment_conflict", payload: {
        "entity_type" => "Edition", "entity_id" => other.id, "source" => "isfdb", "fields" => [ "publisher" ]
      })

      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "Pan Books", "variant_labels[]": [ "Pan Macmillan UK", "Pan Books" ], from_decision_id: @decision.id },
           as: :turbo_stream

      assert_response :success
      assert_match "turbo-stream", @response.media_type
      assert_equal "accepted", @decision.reload.status
      assert_select "turbo-stream[target=pending_decision] template", /Another Book/ # advanced to the next one, rendered ok
    end

    test "the 'other' preferred option uses the free-text value" do
      post settings_authority_terms_url("publisher"),
           params: { preferred_label: "__other__", preferred_label_other: "Pan",
                     "variant_labels[]": [ "Pan Macmillan UK", "Pan Books" ], confirm: "1" }

      assert AuthorityTerm.exists?(vocabulary: "publisher", preferred_label: "Pan")
      assert_equal "Pan", Authority.resolve("publisher", "Pan Books")
    end

    test "an unknown vocabulary is a 404" do
      post settings_authority_terms_url("weather"), params: { preferred_label: "X" }
      assert_response :not_found
    end

    test "retract restores the pre-term value and re-raises the conflict" do
      term = AuthorityTerm.create!(vocabulary: "publisher", preferred_label: "Pan Books")
      term.register_variant("Pan Macmillan UK")
      Authority::Publishers.apply(term)
      assert_empty PendingDecision.pending
      assert_equal "Pan Books", @edition.reload.publisher

      delete settings_authority_term_url("publisher", term)

      assert_redirected_to settings_authority_path("publisher")
      assert_not AuthorityTerm.exists?(term.id)
      assert_equal "Pan Macmillan UK", @edition.reload.publisher # restored from the goodreads record
      assert PendingDecision.pending.where(kind: "enrichment_conflict").exists?
    end
  end
end
