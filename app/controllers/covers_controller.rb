# Provider cover images, through opsimath (docs/CATALOG.md, "Cover
# proxy"): ISFDB's image server trickles each cover out at ~3 KB/s per
# connection (19–27s for one, 2026-11-12), so a page of edition cards took
# most of a minute. A cover in the cache (HasCoverImage) is served from
# disk; one that isn't is fetched into it in the background
# (CoverCacheFetchJob) while this request sends the browser to the
# provider as before — a 20s fetch would tie up one of the web server's
# few threads. Only known cover hosts: this isn't an open proxy.
class CoversController < ApplicationController
  HOSTS = %w[www.isfdb.org isfdb.org covers.openlibrary.org m.media-amazon.com images-na.ssl-images-amazon.com images.amazon.com].freeze

  def self.proxied?(url)
    uri = URI.parse(url.to_s)
    %w[http https].include?(uri.scheme) && HOSTS.include?(uri.host)
  rescue URI::InvalidURIError
    false
  end

  def show
    url = params[:u].to_s
    return head(:bad_request) unless self.class.proxied?(url)

    if (hit = HasCoverImage.cache_read(url))
      expires_in 1.year, public: true
      send_data hit[:io].read, type: hit[:content_type], disposition: "inline", filename: hit[:filename]
    else
      CoverCacheFetchJob.enqueue(url)
      redirect_to url, allow_other_host: true
    end
  end
end
