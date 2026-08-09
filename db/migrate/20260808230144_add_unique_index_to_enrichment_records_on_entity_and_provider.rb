class AddUniqueIndexToEnrichmentRecordsOnEntityAndProvider < ActiveRecord::Migration[8.1]
  def change
    remove_index :enrichment_records, name: "index_enrichment_records_on_entity"
    add_index :enrichment_records, [ :entity_type, :entity_id, :provider ], unique: true, name: "index_enrichment_records_on_entity_and_provider"
  end
end
