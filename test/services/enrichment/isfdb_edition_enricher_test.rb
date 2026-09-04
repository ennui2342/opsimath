require "test_helper"

module Enrichment
  class IsfdbEditionEnricherTest < ActiveSupport::TestCase
    BASE_URL = "http://isfdb-adapter.test:8080"

    # Real response shape, confirmed live (curl against the actual
    # adapter after wiring up its Ingress) for ISBN 0441172717.
    DUNE_RESPONSE = {
      provider: "isfdb", provider_display: "ISFDB", title: "Dune", subtitle: "",
      authors: [ "Frank Herbert" ], publisher: "Ace Books", publish_date: "2010",
      isbn_10: "0441172717", isbn_13: "9780441172719", description: "",
      cover_url: "https://isfdb.org/covers/dune.jpg", language: "eng", page_count: 883,
      categories: [], binding: "pb",
      _isfdb_pub_id: 426303, _isfdb_title_id: 2036, _isfdb_series_id: 869, _isfdb_series_num: 1
    }.freeze

    setup do
      @client = Isfdb::Client.new(base_url: BASE_URL)
      @edition = Edition.create!(format: "paperback")
      EditionIdentifier.create!(edition: @edition, id_type: "isbn10", value: "0441172717")
    end

    test "skips an edition with no isbn identifier at all" do
      bare_edition = Edition.create!(format: "paperback")

      result = IsfdbEditionEnricher.enrich(bare_edition, client: @client)

      assert_equal :skipped, result.status
      assert_equal 0, EnrichmentRecord.count
    end

    test "skips when isfdb-adapter has no match for this isbn (a real 404)" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 404)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :skipped, result.status
    end

    test "reports failure without raising on a service error" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 503)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :failed, result.status
      assert_match(/503/, result.message)
    end

    test "records an EnrichmentRecord and fills blank fields on a real match" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "fake-jpeg-bytes", headers: { "Content-Type" => "image/jpeg" })

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal :success, result.status

      record = EnrichmentRecord.sole
      assert_equal "Edition", record.entity_type
      assert_equal @edition.id, record.entity_id
      assert_equal "isfdb", record.provider
      assert_equal "426303", record.external_id
      assert_equal "Dune", record.raw_payload["title"]

      # Captures what isfdb's fetch literally proposed, independent of
      # what apply_fields decided to do with each one.
      assert_equal "Ace Books", record.fields["publisher"]
      assert_equal "eng", record.fields["language"]
      assert_equal 883, record.fields["page_count"]
      assert_equal "2010", record.fields["publish_date"]
      assert_equal "paperback", record.fields["format"]
      assert_equal "mass_market", record.fields["format_detail"]
      assert_equal "https://isfdb.org/covers/dune.jpg", record.fields["cover_image"]
      # The EnrichmentRecord holds its own downloaded copy of the cover,
      # independent of whatever the Edition itself ends up with.
      assert record.cover_image.attached?
      assert_equal "fake-jpeg-bytes", record.cover_image.download

      assert_equal "Ace Books", @edition.publisher
      assert_equal "eng", @edition.language
      assert_equal 883, @edition.page_count
      assert_equal "2010", @edition.publish_date
      assert_equal "isfdb", @edition.field_sources["publisher"]

      # "pb" -> paperback/mass_market; format was already "paperback" so
      # that's :unchanged, but format_detail was blank so it gets filled.
      assert_equal "paperback", @edition.format
      assert_equal "mass_market", @edition.format_detail

      assert @edition.edition_identifiers.exists?(id_type: "isfdb", value: "426303")
      # ISFDB carries both ISBN forms; the edition only had isbn10, so isbn13 gets filled.
      assert_equal "9780441172719", @edition.edition_identifiers.find_by(id_type: "isbn13")&.value
      assert @edition.cover_image.attached?
      assert_equal "isfdb", @edition.field_sources["cover_image"]
    end

    test "cover_artists (edition-level, ISFDB-only) fills cover_artist, joining multiple credited artists" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(
        status: 200, body: [ DUNE_RESPONSE.merge(cover_artists: [ "Sara Wood", "Jim Tierney" ]) ].to_json
      )
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Sara Wood, Jim Tierney", @edition.reload.cover_artist
      assert_equal "isfdb", @edition.field_sources["cover_artist"]
      assert_equal "Sara Wood, Jim Tierney", EnrichmentRecord.sole.fields["cover_artist"]
    end

    test "no cover_artists in the response leaves cover_artist blank, not an error" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_nil @edition.reload.cover_artist
    end

    test "when an isbn matches multiple isfdb publications, prefers the one whose year matches what's already on file" do
      @edition.update!(publish_date: "1985") # real evidence for which printing this is
      older_printing = DUNE_RESPONSE.merge(publisher: "New English Library", publish_date: "1985", _isfdb_pub_id: 111_111)
      newer_printing = DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "2010", _isfdb_pub_id: 426_303)
      # isfdb-adapter orders most-recent-first — the newer printing leads
      # the array, same as its own single-result default would return.
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ newer_printing, older_printing ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_equal "New English Library", @edition.reload.publisher # the year-matching printing, not the newest
      assert_equal 111_111, EnrichmentRecord.sole.raw_payload["_isfdb_pub_id"]
    end

    test "with no publish_date on file yet and multiple printings, raises an enrichment_printing_choice — doesn't guess" do
      # True for every RSS-auto-created edition — book_published is
      # Work-level, never written to Edition.publish_date.
      assert_nil @edition.publish_date
      newer_printing = DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "2010", _isfdb_pub_id: 426_303, cover_url: "https://isfdb.org/covers/a.jpg")
      older_printing = DUNE_RESPONSE.merge(publisher: "New English Library", publish_date: "1985", _isfdb_pub_id: 111_111, cover_url: "https://isfdb.org/covers/b.jpg")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ newer_printing, older_printing ].to_json)
      stub_request(:get, %r{https://isfdb\.org/covers/}).to_return(status: 200, body: "img", headers: { "Content-Type" => "image/jpeg" })

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :needs_review, result.status
      assert_nil @edition.reload.publisher # nothing applied
      assert_empty EnrichmentRecord.where(entity: @edition) # no fetch committed either

      decision = PendingDecision.sole
      assert_equal "enrichment_printing_choice", decision.kind
      assert_equal @edition.id, decision.payload["entity_id"]
      assert_equal "0441172717", decision.payload["isbn"]
      assert_equal [ 426_303, 111_111 ], decision.payload["candidates"].map { |c| c["_isfdb_pub_id"] }
      assert_equal %w[111111 426303].sort, decision.candidate_covers.map { |a| a.filename.base }.sort # one per printing
    end

    test "when the known year matches no candidate, raises an enrichment_printing_choice rather than guessing newest" do
      @edition.update!(publish_date: "1999") # doesn't match either candidate below
      newer_printing = DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "2010", _isfdb_pub_id: 426_303)
      older_printing = DUNE_RESPONSE.merge(publisher: "New English Library", publish_date: "1985", _isfdb_pub_id: 111_111)
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ newer_printing, older_printing ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "img", headers: { "Content-Type" => "image/jpeg" })

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :needs_review, result.status
      assert_equal "enrichment_printing_choice", PendingDecision.sole.kind
    end

    test "the same ISBN matching several printings but only one for the known year still resolves automatically" do
      @edition.update!(publish_date: "1985")
      a = DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "2010", _isfdb_pub_id: 426_303)
      b = DUNE_RESPONSE.merge(publisher: "New English Library", publish_date: "1985", _isfdb_pub_id: 111_111)
      c = DUNE_RESPONSE.merge(publisher: "Gollancz", publish_date: "2021", _isfdb_pub_id: 222_222)
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ c, a, b ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_equal "New English Library", @edition.reload.publisher
      assert_empty PendingDecision.where(kind: "enrichment_printing_choice")
    end

    test "re-enriching a still-ambiguous edition refreshes the same printing-choice decision, not a second one" do
      a = DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "2010", _isfdb_pub_id: 426_303)
      b = DUNE_RESPONSE.merge(publisher: "New English Library", publish_date: "1985", _isfdb_pub_id: 111_111)
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ a, b ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "img", headers: { "Content-Type" => "image/jpeg" })

      2.times { IsfdbEditionEnricher.enrich(@edition, client: @client) }

      assert_equal 1, PendingDecision.where(kind: "enrichment_printing_choice").count
      assert_equal 2, PendingDecision.sole.candidate_covers.count # not re-attached on the second pass
    end

    # #same_edition? — 2026-09-04, confirmed against the real pending
    # backlog: 74% of raised printing-choice decisions were several ISFDB
    # pub records for the exact same real printing (a collaborative wiki
    # re-entered independently), not a genuine "which one do I own"
    # question. These merge automatically instead of asking a human.

    test "duplicate isfdb records agreeing on everything but publish_date precision merge, preferring the more precise one" do
      less_precise = DUNE_RESPONSE.merge(_isfdb_pub_id: 111_111, publish_date: "2010")
      more_precise = DUNE_RESPONSE.merge(_isfdb_pub_id: 222_222, publish_date: "2010-06")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ less_precise, more_precise ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_empty PendingDecision.where(kind: "enrichment_printing_choice")
      assert_equal "2010-06", @edition.reload.publish_date
      assert_equal 222_222, EnrichmentRecord.sole.raw_payload["_isfdb_pub_id"]
    end

    test "duplicate isfdb records tied on publish_date merge, preferring the one with a cover artist credited" do
      no_artist = DUNE_RESPONSE.merge(_isfdb_pub_id: 111_111)
      with_artist = DUNE_RESPONSE.merge(_isfdb_pub_id: 222_222, cover_artists: [ "John Schoenherr" ])
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ no_artist, with_artist ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_empty PendingDecision.where(kind: "enrichment_printing_choice")
      assert_equal "John Schoenherr", @edition.reload.cover_artist
      assert_equal 222_222, EnrichmentRecord.sole.raw_payload["_isfdb_pub_id"]
    end

    test "a non-distinguishing publisher variant across duplicate isfdb records still merges automatically" do
      plain = DUNE_RESPONSE.merge(_isfdb_pub_id: 111_111, publisher: "Ace Books")
      joined_imprint = DUNE_RESPONSE.merge(_isfdb_pub_id: 222_222, publisher: "Ace Books / Berkley", cover_artists: [ "X" ])
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ plain, joined_imprint ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_empty PendingDecision.where(kind: "enrichment_printing_choice")
      assert_equal "Ace Books / Berkley", @edition.reload.publisher # the richer (more complete) candidate won
    end

    test "a small page-count variance between duplicate isfdb records still merges — the least reliable, least important field here" do
      a = DUNE_RESPONSE.merge(_isfdb_pub_id: 111_111, page_count: 883)
      b = DUNE_RESPONSE.merge(_isfdb_pub_id: 222_222, page_count: 900, cover_artists: [ "X" ]) # ~1.9% apart, richer wins
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ a, b ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_empty PendingDecision.where(kind: "enrichment_printing_choice")
      assert_equal 900, @edition.reload.page_count
    end

    test "a page-count difference beyond the tolerance still raises for review — a real physical difference, not counting noise" do
      a = DUNE_RESPONSE.merge(_isfdb_pub_id: 111_111, page_count: 300)
      b = DUNE_RESPONSE.merge(_isfdb_pub_id: 222_222, page_count: 900)
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ a, b ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :needs_review, result.status
      assert_equal "enrichment_printing_choice", PendingDecision.sole.kind
    end

    test "resolve_candidate_for re-evaluates an already-raised decision's stored candidates without a new fetch" do
      edition = Edition.create!
      candidates = [
        DUNE_RESPONSE.merge(_isfdb_pub_id: 111_111).stringify_keys,
        DUNE_RESPONSE.merge(_isfdb_pub_id: 222_222, cover_artists: [ "X" ]).stringify_keys
      ]

      winner = IsfdbEditionEnricher.resolve_candidate_for(edition, candidates)

      assert_equal 222_222, winner["_isfdb_pub_id"]
      assert_not_requested :get, /isfdb-adapter/
    end

    test "commit_choice applies only the checked fields from the chosen candidate, no conflict gate" do
      @edition.update!(publisher: "Wrong Publisher On File") # would normally be a conflict
      chosen = DUNE_RESPONSE.merge(publisher: "New English Library", publish_date: "1985", page_count: 412, _isfdb_pub_id: 111_111)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "cover-bytes", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.commit_choice(@edition, chosen.deep_stringify_keys, fields: %w[publisher page_count cover_image])

      @edition.reload
      assert_equal "New English Library", @edition.publisher # overwritten, no PendingDecision
      assert_equal 412, @edition.page_count
      assert_nil @edition.publish_date # not checked -> not applied
      assert_equal "isfdb", @edition.field_sources["publisher"]
      assert @edition.cover_image.attached?
      assert_empty PendingDecision.all
      assert_equal "111111", @edition.edition_identifiers.find_by(id_type: "isfdb").value
    end

    test "commit_choice can pick cover_artist like any other field" do
      chosen = DUNE_RESPONSE.merge(cover_artists: [ "John Schoenherr" ], _isfdb_pub_id: 111_111)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.commit_choice(@edition, chosen.deep_stringify_keys, fields: %w[cover_artist])

      assert_equal "John Schoenherr", @edition.reload.cover_artist
    end

    test "reprocess re-applies an already-fetched payload without a new EnrichmentRecord or network call" do
      data = JSON.parse(DUNE_RESPONSE.to_json) # string-keyed, matching a real stored raw_payload
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.reprocess(@edition, data)
      @edition.reload

      assert_equal 0, EnrichmentRecord.count # no new fetch happened
      assert_equal "Ace Books", @edition.publisher
      assert_equal "2010", @edition.publish_date
      assert @edition.edition_identifiers.exists?(id_type: "isfdb", value: "426303")
    end

    test "a genuinely conflicting non-blank field bundles the whole fetch into an edition mismatch, holding back even the fills" do
      @edition.update!(publisher: "Berkley Windhover") # language/page_count/publish_date/etc. all still blank
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # the conflict, untouched
      assert_nil @edition.language # a blank field isn't proof this fetch is safe — held back too

      decision = PendingDecision.where(kind: "enrichment_conflict").sole
      assert_equal %w[publisher language page_count publish_date format_detail cover_image], decision.payload["fields"]
    end

    test "a generic-suffix publisher variant is merged toward the more complete form, real example" do
      @edition.update!(publisher: "Tor")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Tor Books") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Tor Books", @edition.reload.publisher
      assert_equal "isfdb", @edition.field_sources["publisher"]
      assert_equal 0, PendingDecision.count
    end

    test "'&' and the word 'and' are the same connector — no conflict, no change" do
      @edition.update!(publisher: "Faber & Faber")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Faber and Faber") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Faber & Faber", @edition.reload.publisher # untouched — treated as identical
      assert_equal 0, PendingDecision.count
    end

    test "the shorter side of a generic-suffix variant is left alone — already the more complete form" do
      @edition.update!(publisher: "DAW Books")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "DAW") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "DAW Books", @edition.reload.publisher
      assert_equal 0, PendingDecision.count
    end

    test "an isolated region-flavored publisher variant IS merged — it's an ISBN-keyed fact about this exact printing, not a guess" do
      @edition.update!(publisher: "Orbit")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Orbit (US)") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Orbit (US)", @edition.reload.publisher
      assert_equal 0, PendingDecision.count
    end

    test "an imprint/parent form joined by a slash IS merged — same entity with its lineage attached, not a competing name" do
      # "Gollancz" -> "Gollancz / Orion" is ISFDB's house style for
      # imprint-and-parent; the "/" is the tell. Trusted like a territory
      # qualifier — an ISBN-keyed fact about this printing.
      @edition.update!(publisher: "Gollancz")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Gollancz / Orion") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Gollancz / Orion", @edition.reload.publisher
      assert_equal 0, PendingDecision.count
    end

    test "publisher variants differing only by a corporate-form, imprint-line or bracketed-tail qualifier are merged" do
      [
        [ "Bloomsbury", "Bloomsbury Publishing PLC" ],   # legal form
        [ "Gollancz", "Gollancz Paperbacks" ],           # format line
        [ "Tor", "Tor Science Fiction" ],                # genre imprint line
        [ "Arrow Books", "Arrow Books (London)" ],        # bracketed city tail
        [ "Orbit", "Orbit (Hachette)" ],                 # bracketed parent tail
        [ "Berkley Books", "Berkley Books, New York" ]    # comma-led tail
      ].each do |current, proposed|
        edition = Edition.create!
        EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: "0441172717")
        edition.update!(publisher: current)
        plan = IsfdbEditionEnricher.new(edition, client: nil).send(:plan_publisher, proposed)
        assert_includes %i[refine unchanged], plan.action, "#{current.inspect} vs #{proposed.inspect}"
      end
    end

    test "a distinct extra name is still a conflict even when a tail qualifier is also present" do
      @edition.update!(publisher: "Granada")
      plan = IsfdbEditionEnricher.new(@edition, client: nil).send(:plan_publisher, "Panther Granada")
      assert_equal :conflict, plan.action
    end

    test "a publisher name that merely contains the other but adds a distinct name is a conflict, not a silent merge" do
      # "Futura Orbit" contains "Orbit", but "Futura" is a real imprint
      # name, not a generic-form or region word — the containment is a
      # coincidence, so it goes to review rather than being resolved
      # either way. Real production case (pending decision 13).
      @edition.update!(publisher: "Futura Orbit")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Orbit") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Futura Orbit", @edition.reload.publisher # untouched
      decision = PendingDecision.sole
      assert_includes decision.payload["fields"], "publisher"
      diffs = decision.field_diffs.index_by { |d| d[:field] }
      assert_equal "Futura Orbit", diffs["publisher"][:current]
      assert_equal "Orbit", diffs["publisher"][:proposed]
    end

    test "the same distinct-name containment is a conflict in the other direction too — the longer form isn't assumed correct" do
      @edition.update!(publisher: "Orbit")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Futura Orbit") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "Orbit", @edition.reload.publisher # not silently refined to the longer name
      assert_includes PendingDecision.sole.payload["fields"], "publisher"
    end

    test "two fields disagreeing at once bundles into one edition-mismatch review, neither applied nor split into separate field decisions" do
      @edition.update!(publisher: "Berkley Windhover", publish_date: "1978")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "1979-06") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # untouched
      assert_equal "1978", @edition.publish_date # untouched

      decision = PendingDecision.where(kind: "enrichment_conflict").sole
      assert_equal "Edition", decision.payload["entity_type"]
      assert_equal @edition.id, decision.payload["entity_id"]
      # language/page_count/format_detail/cover_image all ride along too,
      # even though only publisher and publish_date actually disagree —
      # once any field's a genuine conflict, the whole fetch is held back
      # together rather than letting the "safe-looking" blanks fill
      # silently (see IsfdbEditionEnricher#apply_fields).
      assert_equal %w[publisher language page_count publish_date format_detail cover_image], decision.payload["fields"]

      diffs = decision.field_diffs.index_by { |d| d[:field] }
      assert_equal "Berkley Windhover", diffs["publisher"][:current]
      assert_equal "Ace Books", diffs["publisher"][:proposed]
      assert_equal "1978", diffs["publish_date"][:current]
      assert_equal "1979-06", diffs["publish_date"][:proposed]
      assert_nil diffs["language"][:current]
      assert_equal "eng", diffs["language"][:proposed]

      # The EnrichmentRecord captures what isfdb literally proposed
      # regardless of the bundle being held back from apply_fields.
      record = EnrichmentRecord.sole
      assert_equal "Ace Books", record.fields["publisher"]
      assert_equal "1979-06", record.fields["publish_date"]
    end

    test "a would-be-safe refinement is held back too when it co-occurs with a genuine conflict on the same edition" do
      # publisher here would be a safe generic-suffix refinement in
      # isolation ("Tor" -> "Tor Books"), but publish_date genuinely
      # conflicts on the same edition — real data shows this co-occurrence
      # pattern means the whole ISBN match likely describes a different
      # specific printing, so the refinement isn't trusted either.
      @edition.update!(publisher: "Tor", publish_date: "1978")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Tor Books", publish_date: "1985") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Tor", @edition.publisher # NOT merged, even though it looked safe in isolation
      assert_equal "1978", @edition.publish_date
      assert PendingDecision.exists?(kind: "enrichment_conflict")
    end

    test "a would-be-safe blank fill is held back too when it co-occurs with a genuine conflict on the same edition" do
      # language/page_count/publish_date would normally auto-fill in
      # isolation (the destination is blank) — but a blank field isn't
      # proof this fetch describes the same printing, so once publisher
      # genuinely conflicts, none of them are trusted silently either.
      @edition.update!(publisher: "Berkley Windhover") # language/page_count/publish_date left blank
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Ace Books") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # the one real conflict, untouched
      assert_nil @edition.language # NOT applied — held back alongside the conflict
      assert_nil @edition.publish_date # NOT applied — held back alongside the conflict

      decision = PendingDecision.where(kind: "enrichment_conflict", status: "pending").sole
      assert_includes decision.payload["fields"], "language"
      assert_includes decision.payload["fields"], "publish_date"
    end

    test "a cover download failure doesn't block the other fields from applying" do
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 500)

      result = IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal :success, result.status
      assert_not @edition.reload.cover_image.attached?
      assert_equal "Ace Books", @edition.publisher
    end

    test "a cover that differs from the one already attached fills outright — isbn already confidently resolved this exact printing" do
      @edition.cover_image.attach(io: StringIO.new("old-cover-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      @edition.update!(field_sources: { "cover_image" => "isfdb" })
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "new-cover-bytes-from-isfdb", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      # No candidate ambiguity at this point (a reused isbn would have
      # raised enrichment_printing_choice instead of ever reaching here)
      # — so a differing cover is just this printing's real cover,
      # applied like any other fill, same as publisher/language/etc.
      assert_equal "new-cover-bytes-from-isfdb", @edition.cover_image.download
      assert_equal "isfdb", @edition.field_sources["cover_image"]
      assert_equal "Ace Books", @edition.publisher
      assert_equal 0, PendingDecision.count
    end

    test "a cover that's byte-identical to the one already attached is a no-op, not noise" do
      @edition.cover_image.attach(io: StringIO.new("same-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      @edition.update!(field_sources: { "cover_image" => "isfdb" })
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "same-bytes", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "same-bytes", @edition.cover_image.download # unchanged
      assert_equal 0, PendingDecision.count
    end

    test "isfdb's cover replaces a Goodreads-sourced cover outright, on the strength of the isbn match — not a general trust hierarchy" do
      # CoverApplier's byte/visual-compare-then-conflict gate is still the
      # rule for everyone else (see cover_applier_test.rb) — this is
      # IsfdbEditionEnricher specifically asserting `authoritative: true`,
      # earned by its own isbn-confident candidate resolution, not ISFDB
      # simply outranking Goodreads.
      @edition.cover_image.attach(io: StringIO.new("goodreads-cover-bytes"), filename: "gr.jpg", content_type: "image/jpeg")
      @edition.update!(field_sources: { "cover_image" => "goodreads" })
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "new-cover-bytes-from-isfdb", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "new-cover-bytes-from-isfdb", @edition.cover_image.download
      assert_equal "isfdb", @edition.field_sources["cover_image"]
      assert_equal 0, PendingDecision.count
    end

    test "a cover conflict co-occurring with a real field conflict bundles into one mismatch with both entries" do
      @edition.update!(publisher: "Berkley Windhover")
      @edition.cover_image.attach(io: StringIO.new("old-cover-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      @edition.update!(field_sources: { "cover_image" => "isfdb" })
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Ace Books") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "new-cover-bytes-from-isfdb", headers: { "Content-Type" => "image/jpeg" })

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      @edition.reload

      assert_equal "Berkley Windhover", @edition.publisher # untouched

      decision = PendingDecision.where(kind: "enrichment_conflict").sole
      assert_equal %w[publisher language page_count publish_date format_detail cover_image], decision.payload["fields"]
    end

    test "re-enriching an edition with an already-unresolved edition mismatch reuses the decision instead of spawning a second one" do
      @edition.update!(publisher: "Berkley Windhover", publish_date: "1978")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publisher: "Ace Books", publish_date: "1979-06") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)
      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal 1, PendingDecision.where(kind: "enrichment_conflict").count
    end

    test "a more precise publish_date from isfdb is applied as a refinement, not flagged as a conflict" do
      @edition.update!(publish_date: "2010")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publish_date: "2010-06") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2010-06", @edition.reload.publish_date
      assert_equal "isfdb", @edition.field_sources["publish_date"]
      assert_equal 0, PendingDecision.count
    end

    test "a less precise publish_date from isfdb is left alone — we already know more" do
      @edition.update!(publish_date: "2010-06-15")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE.merge(publish_date: "2010") ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2010-06-15", @edition.reload.publish_date
      assert_equal 0, PendingDecision.count
    end

    test "the same publish_date value at the same precision is a no-op, not a conflict" do
      @edition.update!(publish_date: "2010")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2010", @edition.reload.publish_date
      assert_equal 0, PendingDecision.count
    end

    test "a genuinely different publish_date (neither value extends the other) is a real conflict" do
      @edition.update!(publish_date: "2011")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ DUNE_RESPONSE ].to_json) # "2010"
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "2011", @edition.reload.publish_date # untouched
      decision = PendingDecision.where(kind: "enrichment_conflict").where("payload @> ?", { fields: [ "publish_date" ] }.to_json).sole
      diff = decision.field_diffs.find { |d| d[:field] == "publish_date" }
      assert_equal "2011", diff[:current]
      assert_equal "2010", diff[:proposed]
    end

    test "unmapped pub_ptype values are left alone rather than guessed at" do
      response = DUNE_RESPONSE.merge(binding: "quarto")
      stub_request(:get, "#{BASE_URL}/isbn/0441172717?all=true").to_return(status: 200, body: [ response ].to_json)
      stub_request(:get, "https://isfdb.org/covers/dune.jpg").to_return(status: 200, body: "x")

      IsfdbEditionEnricher.enrich(@edition, client: @client)

      assert_equal "paperback", @edition.reload.format # untouched default, not guessed from "quarto"
      assert_nil @edition.format_detail
    end
  end
end
