module BookListWants
  # Turns a BookListWant into wants (docs/LISTS.md): every book on the list
  # in its scope (the winners, or the whole shortlist; from a year, if set)
  # that Mark doesn't own, isn't already wanted and isn't excluded becomes
  # a want — added to the catalogue first if it isn't there. Only entries
  # matched to an ISFDB title: an unmatched one is never collected blindly.
  class Sync
    def self.run(book_list_want) = new(book_list_want).run

    def self.run_all = BookListWant.includes(:book_list).find_each.sum { |w| run(w) }

    def initialize(book_list_want)
      @list_want = book_list_want
    end

    # -> number of new wants
    def run
      view = BookListView.for(@list_want.book_list)
      added = view.missing.select { |e| e.isfdb_title_id && @list_want.covers?(e.entry) && !@list_want.excluded?(e.isfdb_title_id) }
                  .count { |e| self.class.want_entry(@list_want.book_list, e, book_list_want: @list_want) }
      @list_want.update!(synced_at: Time.current)
      added
    end

    # One book from the list's page: into the catalogue and wanted.
    def self.want_entry(list, entry, book_list_want: nil)
      work = entry.work || AddBook::Create.create_work("title" => entry.title, "authors" => entry.author.to_s.split(/ and | & /).map(&:strip),
                                                       "first_year" => entry.year,
                                                       "provider_works" => [ { "provider" => "isfdb", "id" => entry.isfdb_title_id.to_s } ])
      return false if work.want

      want = work.create_want!(book_list_want:)
      WantPrintingsJob.perform_later(want.id)
      CatalogueEvent.record(kind: "wanted", origin: (book_list_want ? "book_list_wants" : nil), work:,
                            summary: "#{"Collecting #{list.name}: " if book_list_want}wanted #{work.title}#{" (#{entry.year})" if entry.year}")
      true
    end
  end
end
