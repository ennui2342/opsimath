# A provider cover into the cover cache (CoversController): fetched once,
# served from disk ever after.
class CoverCacheFetchJob < ApplicationJob
  queue_as :default

  # Once per URL while one's queued or running: a page of cards asks for
  # each cover on every view until it's cached.
  def self.enqueue(url)
    return if HasCoverImage.cached?(url)
    return unless Rails.cache.write("cover-fetch:#{Digest::SHA1.hexdigest(url)}", true, expires_in: 10.minutes, unless_exist: true)

    perform_later(url)
  end

  def perform(url)
    HasCoverImage.fetch_image(url) unless HasCoverImage.cached?(url)
  end
end
