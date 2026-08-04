class CreateEnrichmentRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :enrichment_records do |t|
      t.references :entity, polymorphic: true, null: false
      t.string :provider, null: false
      t.string :external_id, null: false
      t.datetime :fetched_at, null: false
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end
  end
end
