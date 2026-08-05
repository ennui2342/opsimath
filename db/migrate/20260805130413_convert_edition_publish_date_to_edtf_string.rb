class ConvertEditionPublishDateToEdtfString < ActiveRecord::Migration[8.1]
  # Edition.publish_date + publish_date_precision, a `date` column paired
  # with a separate enum, forced a fabricated day-of-month into the date
  # column whenever only the year (or year+month) was actually known —
  # `publish_date_precision` was added to compensate for that, but the
  # `date` column itself still silently lied without it. Replaced with a
  # single EDTF-formatted string ("1978", "1978-06", or "1978-06-15") that
  # only ever contains the digits actually known — no companion field
  # needed to interpret it correctly. See docs/DATA_MODEL.md.
  def up
    add_column :editions, :publish_date_edtf, :string

    execute <<~SQL.squish
      UPDATE editions SET publish_date_edtf = CASE publish_date_precision
        WHEN 'year' THEN to_char(publish_date, 'YYYY')
        WHEN 'month' THEN to_char(publish_date, 'YYYY-MM')
        WHEN 'day' THEN to_char(publish_date, 'YYYY-MM-DD')
        ELSE NULL
      END
      WHERE publish_date IS NOT NULL
    SQL

    remove_column :editions, :publish_date
    remove_column :editions, :publish_date_precision
    rename_column :editions, :publish_date_edtf, :publish_date
  end

  def down
    add_column :editions, :publish_date_date, :date
    add_column :editions, :publish_date_precision, :string

    execute <<~SQL.squish
      UPDATE editions SET
        publish_date_date = CASE length(publish_date)
          WHEN 4 THEN (publish_date || '-01-01')::date
          WHEN 7 THEN (publish_date || '-01')::date
          ELSE publish_date::date
        END,
        publish_date_precision = CASE length(publish_date)
          WHEN 4 THEN 'year'
          WHEN 7 THEN 'month'
          ELSE 'day'
        END
      WHERE publish_date IS NOT NULL
    SQL

    remove_column :editions, :publish_date
    rename_column :editions, :publish_date_date, :publish_date
  end
end
