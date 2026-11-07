# Nightly, after the providers' printing lists are refreshed: each edition
# brought up to date from the printing it's anchored to (AnchoredRefresh,
# docs/CATALOG.md "Anchored editions", step 3).
class AnchoredRefreshJob < ApplicationJob
  queue_as :default

  def perform
    changed = AnchoredRefresh.apply
    Rails.logger.info("anchored refresh: #{changed} editions changed")
    changed
  end
end
