module Goodreads
  # Builds one `Edition` for a `Work` from a Goodreads feed item — the
  # shared path for `ShelfSync`'s auto-create and
  # `EditionReconciliationResolver`'s change_edition / add_edition /
  # unowned_read. Records the feed's cover through the standard
  # `Enrichment::SourceRecorder` policy, same as a matched edition.
  #
  # Deliberately does **not** create a `Copy` — the caller decides
  # ownership (an owned `Copy`, or none for a library/borrowed read).
  class EditionBuilder
    def self.build(work:, item:) = new(work, item).build

    def initialize(work, item)
      @work = work
      @item = item
    end

    def build
      ActiveRecord::Base.transaction do
        edition = Edition.create!
        EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: @item.goodreads_book_id)
        # RSS only carries isbn10; derive isbn13 so a shop scan matches (docs/MOBILE.md).
        EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: @item.isbn) if @item.isbn.present?
        edition.backfill_isbn_pair!
        Enrichment::SourceRecorder.record(
          entity: edition, provider: "goodreads", external_id: @item.goodreads_book_id,
          raw_payload: @item.to_h, fields: { cover_image: @item.book_image_url }
        )
        EditionContent.create!(edition: edition, work: @work)
        edition
      end
    end
  end
end
