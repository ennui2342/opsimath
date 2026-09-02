module Isfdb
  # Every edition ISFDB knows for a Work — looked up via
  # /isbn/{isbn}/editions on one of the work's own ISBNs (any printing's
  # ISBN resolves to the same ISFDB title, so the first that returns
  # anything wins). Format-agnostic: returns the adapter's raw edition
  # hashes and lets the caller take what it needs.
  #
  # Deliberately a standalone read, not persisted: opsimath treats ISFDB
  # as a live source, not a mirror to sync (see docs/MOBILE.md). The
  # mobile snapshot build derives sibling ISBNs from this; a future
  # "switch edition" picker in the web app would call it the same way.
  class WorkEditions
    def self.for(work, client: Client.new) = new(work, client:).call

    def initialize(work, client:)
      @work = work
      @client = client
    end

    # -> [Hash] adapter edition records, possibly empty. A missing match
    # is not an error (returns []); a real adapter failure propagates as
    # Isfdb::ServiceError.
    def call
      source_isbns.each do |isbn|
        editions = @client.lookup_editions(isbn)
        return editions if editions.any?
      end
      []
    end

    private

    # ISBN-13 first (what the adapter's own examples use), then ISBN-10.
    def source_isbns
      @work.editions
           .flat_map(&:edition_identifiers)
           .select { |i| i.id_type == "isbn13" || i.id_type == "isbn10" }
           .sort_by { |i| i.id_type == "isbn13" ? 0 : 1 }
           .map(&:value)
           .uniq
    end
  end
end
