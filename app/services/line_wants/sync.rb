module LineWants
  # Turns a LineWant into wants (docs/CATALOG.md, "Publication series"):
  # every number in the line that isn't Mark's — not one he has in that
  # printing; a book he has in another edition counts, since collecting
  # the line means having its printing — and isn't excluded, becomes a want
  # hunting *that printing*. A book not yet in the catalogue is added, as a
  # wanted book. Only from the full line (isfdb-adapter's /pubseries), never
  # a partial list.
  class Sync
    def self.run(line_want) = new(line_want).run

    def self.run_all = LineWant.find_each.sum { |lw| run(lw) }

    def initialize(line_want)
      @line_want = line_want
    end

    # -> number of new wants (or printings newly wanted)
    def run
      line = PublicationLine.find(@line_want.pub_series_id)
      return 0 unless line.complete

      @line_want.update!(name: line.name)
      added = line.entries.reject { |e| e.status == :yours || @line_want.excluded?(e.pub_id) }.count { |e| want(e, line) }
      @line_want.update!(synced_at: Time.current)
      added
    end

    private

    def want(entry, line)
      work = entry.work || create_work(entry) or return false
      want = work.want || work.create_want!(line_want: @line_want).tap { WantPrintingsJob.perform_later(it.id) }
      ids = Array(want.printing_override_ids)
      return false if ids.include?(entry.pub_id)

      # A want of Mark's own that hunts by the collecting rule keeps those
      # covers and gains this printing.
      base = want.printing_override_ids.nil? && want.line_want_id.nil? ? CollectingProfile.current.verdict(want).wanted.map(&:isfdb_pub_id) : ids
      want.update!(printing_override_ids: (base | [ entry.pub_id ]))
      CatalogueEvent.record(kind: "wanted", origin: "line_wants", work:,
                            summary: "Collecting #{line.name}: wanted #{"##{entry.number} " if entry.number}#{work.title} (#{[ entry.publisher, entry.year ].compact.join(' ')})")
      true
    end

    # A number not yet in the catalogue: a new book, as Add a book's "Want
    # it" makes one — its ISFDB title id, so the nightly lookup finds its
    # printings (this one among them).
    def create_work(entry)
      return unless entry.title_id

      AddBook::Create.create_work("title" => entry.title, "authors" => entry.authors,
                                  "provider_works" => [ { "provider" => "isfdb", "id" => entry.title_id.to_s } ])
    end
  end
end
