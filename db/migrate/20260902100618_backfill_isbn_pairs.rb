# Fill the missing half of the ISBN-10/13 pair on every existing edition
# that has exactly one and where the other is derivable. The shop-lookup
# PWA (docs/MOBILE.md constraint 1) matches barcode scans against
# ISBN-13, and going forward the ingestion paths derive it — this catches
# up the ~40 editions imported before that. Deterministic (Isbn.to_13 /
# to_10), so no source tracking; re-runnable.
class BackfillIsbnPairs < ActiveRecord::Migration[8.1]
  def up
    Edition.reset_column_information
    Edition
      .joins(:edition_identifiers)
      .where(edition_identifiers: { id_type: %w[isbn10 isbn13] })
      .distinct
      .find_each(&:backfill_isbn_pair!)
  end

  def down
    # no-op — a derived identifier is not distinguishable from an
    # imported one and dropping it would lose real data
  end
end
