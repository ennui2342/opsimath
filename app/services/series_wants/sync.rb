module SeriesWants
  # Turns a SeriesWant into wants (docs/CATALOG.md, "Series pages"): every
  # English book ISFDB files in the series that Mark doesn't own, isn't
  # already wanted and isn't excluded becomes a want for the book — added
  # to the catalogue first if it isn't there, filed in the series. Only from
  # ISFDB's full list, never a partial one.
  class Sync
    def self.run(series_want) = new(series_want).run

    def self.run_all = SeriesWant.includes(:series).find_each.sum { |sw| run(sw) }

    def initialize(series_want)
      @series_want = series_want
    end

    # -> number of new wants
    def run
      volumes = SeriesVolumes.for(@series_want.series)
      return 0 unless volumes.complete

      added = volumes.missing.reject { |e| e.title_id && @series_want.excluded?(e.title_id) }.count { |e| want(e) }
      @series_want.update!(synced_at: Time.current)
      added
    end

    # One book from the series page: into the catalogue and wanted.
    def self.want_volume(series, entry, series_want: nil)
      work = entry.work || AddBook::Create.create_work("title" => entry.title, "authors" => entry.authors,
                                                       "provider_works" => [ { "provider" => "isfdb", "id" => entry.title_id.to_s } ])
      WorkSeries.find_or_create_by!(work:, series:) { |ws| ws.position = entry.position }
      return false if work.want

      want = work.create_want!(series_want:)
      WantPrintingsJob.perform_later(want.id)
      CatalogueEvent.record(kind: "wanted", origin: (series_want ? "series_wants" : nil), work:,
                            summary: "#{"Collecting #{series.name}: " if series_want}wanted #{"##{format('%g', entry.position)} " if entry.position}#{work.title}")
      true
    end

    private

    def want(entry) = entry.title_id ? self.class.want_volume(@series_want.series, entry, series_want: @series_want) : false
  end
end
