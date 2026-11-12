# Nightly, gently: the covers Mark is most likely to look at — the ISFDB
# printings of books he owns or wants — into the cover cache, one at a
# time, a few hundred a night (Mark, 2026-11-12). ISFDB is volunteer-run
# and throttles; this never fetches in bulk or in parallel.
class CoverCacheWarmJob < ApplicationJob
  queue_as :default

  PER_NIGHT = 300
  DEADLINE = 2.hours

  def perform
    started = Time.current
    work_ids = Work.where(id: Copy.where(disposition: "owned").joins(edition: :edition_contents).select("edition_contents.work_id"))
                   .or(Work.where(id: Want.select(:work_id))).select(:id)
    urls = ProviderEdition.where(work_id: work_ids).where.not(cover_url: [ nil, "" ]).distinct.pluck(:cover_url)
                          .select { |u| CoversController.proxied?(u) && !HasCoverImage.cached?(u) }
    fetched = urls.first(PER_NIGHT).take_while { Time.current - started < DEADLINE }.count { |u| HasCoverImage.fetch_image(u) }
    Rails.logger.info("cover cache warm: #{fetched} fetched, #{[ urls.size - PER_NIGHT, 0 ].max} left for later nights")
    fetched
  end
end
