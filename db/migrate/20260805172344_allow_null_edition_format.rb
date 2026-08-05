class AllowNullEditionFormat < ActiveRecord::Migration[8.1]
  # Edition.format was NOT NULL because Phase 1's CSV import always had
  # *some* Binding value to map (even "Unknown Binding"). Phase 2's
  # Goodreads RSS feed has no binding/format field at all — forcing a
  # value there would fabricate data, the same false-precision problem
  # publish_date's EDTF fix already solved. See docs/INTEGRATIONS.md.
  def change
    change_column_null :editions, :format, true
  end
end
