module Settings
  # Book titles worded differently on ISFDB (TitleCleanup's :different):
  # a UK/US title, a marketing subtitle, or a book linked to the wrong ISFDB
  # record. Mark takes ISFDB's, keeps his (never asked again), or goes to
  # the book to fix its printing.
  class TitlesController < ApplicationController
    def index
      @fixes = TitleCleanup.plan.select { |f| f.kind == :different }.sort_by { |f| f.from.downcase }
    end

    def update
      work = Work.find(params[:id])
      if params[:choice] == "isfdb"
        TitleCleanup.retitle(work, TitleCleanup.isfdb_title(work), source: "isfdb")
        notice = "Now “#{work.title}”."
      else
        TitleCleanup.retitle(work, work.title, source: "manual")
        notice = "Kept “#{work.title}”."
      end
      redirect_to settings_titles_path, notice:
    end
  end
end
