class AddFieldsToEnrichmentRecords < ActiveRecord::Migration[8.1]
  def change
    add_column :enrichment_records, :fields, :jsonb, default: {}, null: false
  end
end
