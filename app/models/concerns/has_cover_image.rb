require "net/http"
require "stringio"

# Shared cover-download helper for the models that hold a `cover_image`
# Active Storage attachment (EnrichmentRecord, and via HasCoverThumbnail,
# Edition / WishlistItem). Each model still declares its own
# `has_one_attached :cover_image` — plain, or with the :thumb variant.
module HasCoverImage
  extend ActiveSupport::Concern

  # Download an image URL straight into cover_image. Best-effort: a failed
  # or non-image fetch is logged and swallowed, never raised — a missing
  # cover is not a reason to fail the surrounding operation.
  def attach_cover_from_url(url)
    data = HasCoverImage.fetch_image(url)
    cover_image.attach(**data) if data
  end

  # Fetch an image URL to an attachable `{io:, filename:, content_type:}`
  # hash, or nil on any failure (same swallow-and-log contract). Lets a
  # caller with more than one cover to hold — PendingDecision's
  # candidate_covers for enrichment_printing_choice — reuse the download.
  def self.fetch_image(url)
    return if url.blank?

    uri = URI.parse(url)
    return unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.get_response(uri)
    return unless response.is_a?(Net::HTTPSuccess)

    { io: StringIO.new(response.body),
      filename: File.basename(uri.path).presence || "cover.jpg",
      content_type: response.content_type || "image/jpeg" }
  rescue StandardError => e
    Rails.logger.warn("image fetch failed for #{url}: #{e.message}")
    nil
  end
end
