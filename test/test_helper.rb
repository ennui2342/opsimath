ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Global, low-priority stub for cover-image downloads
    # (Goodreads::ShelfSync#attach_cover) — most tests that happen to
    # auto-create an Edition via a real fixture item aren't testing cover
    # behavior at all and shouldn't need to know or care that one exists.
    # A test that specifically wants to exercise cover attachment can
    # register its own more specific stub_request for the same URL,
    # which WebMock matches in preference to this one.
    #
    # Same reasoning for the cover-compare sidecar (Enrichment::CoverApplier)
    # — default to "confirmed different" (ratio: 0.0) so the many existing
    # tests asserting "a populated destination with differing bytes is a
    # real conflict" keep meaning what they say without each one having to
    # know the sidecar exists. WebMock's own NetConnectNotAllowedError is
    # deliberately NOT a StandardError (so test code can't accidentally
    # swallow "you made a real network call" the way CoverCompareClient's
    # rescue swallows a genuine outage) — found live: with no stub here,
    # every such test raised instead of exercising the conflict it meant
    # to test. A test that wants the "visually the same" path injects its
    # own client double instead (see cover_applier_test.rb) — real
    # similarity-scoring behavior is validated by the sidecar's own
    # Python test suite (services/cover_compare/test_app.py) and by the
    # empirical eval, not by faking scores here.
    setup do
      stub_request(:get, /i\.gr-assets\.com/).to_return(status: 200, body: "fake-cover-bytes", headers: { "Content-Type" => "image/jpeg" })
      stub_request(:post, %r{/compare\z}).to_return(status: 200, body: { ratio: 0.0, inliers: 0 }.to_json, headers: { "Content-Type" => "application/json" })
    end

    # Add more helper methods to be used by all tests here...
  end
end
