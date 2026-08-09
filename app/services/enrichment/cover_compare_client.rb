require "net/http"
require "json"
require "securerandom"

module Enrichment
  # Thin HTTP client for the local cover-compare sidecar
  # (services/cover_compare/) — a pure ORB+RANSAC image-similarity score,
  # no policy attached. See that service's own app.py header for what
  # `ratio` means and why ORB was chosen over perceptual hashing.
  #
  # Deliberately fails soft: any connection problem, timeout, or
  # unexpected response returns nil rather than raising. Unlike
  # Isfdb::Client (a hard dependency enrichment can't proceed without),
  # this is a volume-reduction optimization on top of CoverApplier's
  # existing byte-exact comparison — if the sidecar is down or
  # unconfigured, CoverApplier falls back to today's byte-diff-means-
  # conflict behavior, which is always correct, just noisier.
  class CoverCompareClient
    Result = Struct.new(:ratio, :inliers, keyword_init: true)

    def initialize(base_url: ENV.fetch("COVER_COMPARE_URL", nil))
      @base_url = base_url
    end

    def compare(bytes_a, bytes_b)
      return nil if @base_url.blank?

      response = post(bytes_a, bytes_b)
      return nil unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      Result.new(ratio: data["ratio"], inliers: data["inliers"])
    rescue StandardError => e
      Rails.logger.warn("cover-compare request failed, falling back to byte comparison: #{e.class}: #{e.message}")
      nil
    end

    private

    def post(bytes_a, bytes_b)
      uri = URI.join(@base_url, "/compare")
      boundary = SecureRandom.hex(16)

      Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 8) do |http|
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        request.body = multipart_body(boundary, bytes_a, bytes_b)
        http.request(request)
      end
    end

    def multipart_body(boundary, bytes_a, bytes_b)
      "#{file_part(boundary, "image_a", bytes_a)}" \
      "#{file_part(boundary, "image_b", bytes_b)}" \
      "--#{boundary}--\r\n"
    end

    def file_part(boundary, name, bytes)
      "--#{boundary}\r\n" \
      "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{name}.jpg\"\r\n" \
      "Content-Type: application/octet-stream\r\n\r\n" \
      "#{bytes}\r\n"
    end
  end
end
