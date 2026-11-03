# A book just wanted: its printings fetched (KnownEditionsRefresh) and its
# covers grouped (WishlistCoverGrouping) now, so its bargain-hunting page
# fills in within a minute rather than after the nightly runs.
class WantPrintingsJob < ApplicationJob
  queue_as :default

  def perform(want_id)
    want = Want.find_by(id: want_id) or return
    KnownEditionsRefresh.refresh_work(want.work)
    WishlistCoverGrouping.run(Want.where(id: want.id).includes(work: [ :provider_editions, { work_contributors: :contributor } ]))
  end
end
