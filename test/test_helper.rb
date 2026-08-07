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
    setup do
      stub_request(:get, /i\.gr-assets\.com/).to_return(status: 200, body: "fake-cover-bytes", headers: { "Content-Type" => "image/jpeg" })
    end

    # Add more helper methods to be used by all tests here...
  end
end
