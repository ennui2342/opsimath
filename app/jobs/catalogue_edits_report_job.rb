# Every 15 minutes: Mark's catalogue edits since the last post, to
# Discord's #catalogue (CatalogueReport). Posts nothing when nothing changed.
class CatalogueEditsReportJob < ApplicationJob
  queue_as :default

  def perform = CatalogueReport.post_edits
end
