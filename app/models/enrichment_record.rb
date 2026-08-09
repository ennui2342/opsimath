require "net/http"

class EnrichmentRecord < ApplicationRecord
  belongs_to :entity, polymorphic: true

  # Every source's own proposed cover, kept locally — not hotlinked, same
  # "keep what was fetched" reasoning as `raw_payload`. Downloaded once,
  # regardless of whether anything about this fetch turns out to be in
  # conflict, so it's already sitting here the moment a review screen (or
  # a future image-comparison pass) needs it, instead of re-fetching from
  # a provider URL that can go stale or disappear. Replaces the old
  # Edition#candidate_cover_image staging slot entirely: once every
  # EnrichmentRecord durably holds its own cover, there's nothing left
  # for a separate "proposed cover" attachment on Edition to do.
  has_one_attached :cover_image

  validates :provider, presence: true
  validates :external_id, presence: true
  validates :fetched_at, presence: true
  # One row per (entity, provider) — Mark, 2026-08-08/09: "there is a
  # single enrichment source Goodreads, that record might vary over time
  # as it's updated... there should never be two records for the same
  # ISBN." A provider's later fetch updates this same row in place (see
  # Enrichment::SourceRecorder.record) rather than creating a second one
  # — matched by the DB's own unique index, this is the app-level version
  # of the same guarantee, so a direct .create! bypassing SourceRecorder
  # fails loudly instead of silently violating the invariant.
  validates :provider, uniqueness: { scope: %i[entity_type entity_id] }

  # The one lookup "what does this source currently say" needs, shared by
  # PendingDecision#field_diffs, PendingDecision#field_candidates,
  # IsfdbEditionEnricher's own cover handling, and anywhere else that
  # needs "the current record from this provider for this entity." Kept
  # named `latest` for call-site continuity even though there's now at
  # most one row to find — a provider's later fetch updates the same row
  # rather than adding another one to order against.
  def self.latest(entity:, provider:)
    find_by(entity: entity, provider: provider)
  end

  def attach_cover_from_url(url)
    return if url.blank?

    uri = URI.parse(url)
    return unless %w[http https].include?(uri.scheme)

    response = Net::HTTP.get_response(uri)
    return unless response.is_a?(Net::HTTPSuccess)

    cover_image.attach(
      io: StringIO.new(response.body),
      filename: File.basename(uri.path).presence || "cover.jpg",
      content_type: response.content_type || "image/jpeg"
    )
  rescue StandardError => e
    Rails.logger.warn("cover download failed for enrichment_record #{id}: #{e.message}")
  end
end
