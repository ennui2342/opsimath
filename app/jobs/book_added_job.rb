# A book just added: its printings fetched (KnownEditionsRefresh), its
# ISFDB main title, form, year and language (Isfdb::MainTitles), its
# series filed from them (WorkSeriesSync) and its editions brought up to
# date from them (AnchoredRefresh) now, rather
# than after the nightly runs — so an edition added from Open Library
# gets ISFDB's cover artist within a minute when ISFDB has its printing.
class BookAddedJob < ApplicationJob
  queue_as :default

  def perform(work_id)
    work = Work.find_by(id: work_id) or return
    KnownEditionsRefresh.refresh_work(work)
    Isfdb::MainTitles.run(Work.where(id: work.id)) # its form, year and language from ISFDB
    WorkSeriesSync.run(Work.where(id: work.id))
    AnchoredRefresh.apply(AnchoredRefresh.default_scope.where(id: work.editions.select(:id)))
  end
end
