require "net/http"
require "stringio"
require "digest"
require "fileutils"

# Shared cover-download helper for the models that hold a `cover_image`
# Active Storage attachment (EnrichmentRecord, and via HasCoverThumbnail,
# Edition / Want). Each model still declares its own
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
  #
  # A URL already in the cover cache is served from disk instead of
  # re-fetched, and every real fetch is written back to it. Provider cover
  # URLs are stable content addresses, so reusing them is free. Added for
  # `goodreads:rebuild` (2026-09-05) as opt-in; on everywhere since
  # 2026-11-12, when it also backs the cover proxy (CoversController) —
  # ISFDB's image server trickles each cover out at ~3 KB/s.
  MAX_REDIRECTS = 3

  def self.fetch_image(url)
    return if url.blank?
    if (hit = cache_read(url))
      return hit
    end

    uri = URI.parse(url)
    response = nil
    # Open Library's cover ids answer with a redirect to archive.org.
    MAX_REDIRECTS.succ.times do
      return unless %w[http https].include?(uri.scheme)

      response = Net::HTTP.get_response(uri)
      break unless response.is_a?(Net::HTTPRedirection) && response["location"].present?

      uri = uri + response["location"]
    end
    return unless response.is_a?(Net::HTTPSuccess)

    filename = File.basename(URI.parse(url).path).presence || "cover.jpg"
    content_type = response.content_type || "image/jpeg"
    cache_write(url, response.body, filename, content_type)
    { io: StringIO.new(response.body), filename: filename, content_type: content_type }
  rescue StandardError => e
    Rails.logger.warn("image fetch failed for #{url}: #{e.message}")
    nil
  end

  # ENV["COVER_CACHE_DIR"], else storage/cover_cache (on the volume web and
  # worker share in production); none in tests unless set.
  def self.cover_cache_dir
    ENV["COVER_CACHE_DIR"].presence || (Rails.root.join("storage", "cover_cache").to_s unless Rails.env.test?)
  end

  def self.cached?(url) = !!(cover_cache_dir && url.present? && cache_paths(url).all? { |path| File.exist?(path) })

  # <dir>/<sha1(url)> holds the raw bytes, <sha1(url)>.json the
  # filename/content_type/url — everything cover_image.attach needs.
  def self.cache_paths(url)
    base = File.join(cover_cache_dir, Digest::SHA1.hexdigest(url))
    [ base, "#{base}.json" ]
  end

  def self.cache_read(url)
    return unless cover_cache_dir

    bytes_path, meta_path = cache_paths(url)
    return unless File.exist?(bytes_path) && File.exist?(meta_path)

    meta = JSON.parse(File.read(meta_path))
    { io: StringIO.new(File.binread(bytes_path)), filename: meta["filename"], content_type: meta["content_type"] }
  rescue StandardError => e
    Rails.logger.warn("cover cache read failed for #{url}: #{e.message}")
    nil
  end

  def self.cache_write(url, bytes, filename, content_type)
    return unless cover_cache_dir

    FileUtils.mkdir_p(cover_cache_dir)
    bytes_path, meta_path = cache_paths(url)
    File.binwrite(bytes_path, bytes)
    File.write(meta_path, JSON.generate(url: url, filename: filename, content_type: content_type))
  rescue StandardError => e
    Rails.logger.warn("cover cache write failed for #{url}: #{e.message}")
  end
end
