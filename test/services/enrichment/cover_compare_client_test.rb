require "test_helper"

module Enrichment
  class CoverCompareClientTest < ActiveSupport::TestCase
    BASE_URL = "http://cover-compare.test:8000"

    test "returns a Result with the ratio and inliers on success" do
      stub_request(:post, "#{BASE_URL}/compare").to_return(
        status: 200, body: { ratio: 0.42, inliers: 300, keypoints_a: 900, keypoints_b: 850 }.to_json
      )
      client = CoverCompareClient.new(base_url: BASE_URL)

      result = client.compare("bytes-a", "bytes-b")

      assert_equal 0.42, result.ratio
      assert_equal 300, result.inliers
    end

    test "returns nil on a non-2xx response rather than raising" do
      stub_request(:post, "#{BASE_URL}/compare").to_return(status: 422, body: { detail: "not decodable" }.to_json)
      client = CoverCompareClient.new(base_url: BASE_URL)

      assert_nil client.compare("bytes-a", "bytes-b")
    end

    test "returns nil when the service is unreachable rather than raising" do
      stub_request(:post, "#{BASE_URL}/compare").to_timeout
      client = CoverCompareClient.new(base_url: BASE_URL)

      assert_nil client.compare("bytes-a", "bytes-b")
    end

    test "returns nil when no base_url is configured, without attempting a request" do
      client = CoverCompareClient.new(base_url: nil)

      assert_nil client.compare("bytes-a", "bytes-b")
    end

    test "sends both images as multipart file parts" do
      stub = stub_request(:post, "#{BASE_URL}/compare")
        .with { |request| request.body.include?("bytes-a") && request.body.include?("bytes-b") && request.headers["Content-Type"].start_with?("multipart/form-data") }
        .to_return(status: 200, body: { ratio: 1.0, inliers: 500 }.to_json)
      client = CoverCompareClient.new(base_url: BASE_URL)

      client.compare("bytes-a", "bytes-b")

      assert_requested stub
    end
  end
end
