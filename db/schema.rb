# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_02_193553) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "awards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.string "wikidata_id"
  end

  create_table "contributors", force: :cascade do |t|
    t.text "bio"
    t.datetime "created_at", null: false
    t.jsonb "external_ids", default: {}, null: false
    t.jsonb "field_sources", default: {}, null: false
    t.string "name", null: false
    t.string "sort_name"
    t.datetime "updated_at", null: false
  end

  create_table "copies", force: :cascade do |t|
    t.date "acquired_date"
    t.decimal "acquired_price", precision: 10, scale: 2
    t.string "acquired_source"
    t.string "condition"
    t.datetime "created_at", null: false
    t.string "disposition", default: "owned", null: false
    t.bigint "edition_id", null: false
    t.text "inscription"
    t.text "notes"
    t.bigint "storage_location_id"
    t.datetime "updated_at", null: false
    t.index ["edition_id"], name: "index_copies_on_edition_id"
    t.index ["storage_location_id"], name: "index_copies_on_storage_location_id"
  end

  create_table "edition_contents", force: :cascade do |t|
    t.string "billing"
    t.datetime "created_at", null: false
    t.integer "display_order"
    t.bigint "edition_id", null: false
    t.integer "page_start"
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["edition_id"], name: "index_edition_contents_on_edition_id"
    t.index ["work_id"], name: "index_edition_contents_on_work_id"
  end

  create_table "edition_contributors", force: :cascade do |t|
    t.bigint "contributor_id", null: false
    t.datetime "created_at", null: false
    t.string "credited_as"
    t.integer "display_order"
    t.bigint "edition_id", null: false
    t.string "role", null: false
    t.datetime "updated_at", null: false
    t.index ["contributor_id"], name: "index_edition_contributors_on_contributor_id"
    t.index ["edition_id", "contributor_id", "role"], name: "index_edition_contributors_on_edition_contributor_role", unique: true
    t.index ["edition_id"], name: "index_edition_contributors_on_edition_id"
  end

  create_table "edition_identifiers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "edition_id", null: false
    t.string "id_type"
    t.string "notes"
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["edition_id"], name: "index_edition_identifiers_on_edition_id"
  end

  create_table "editions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.string "edition_name"
    t.jsonb "field_sources", default: {}, null: false
    t.string "format"
    t.string "format_detail"
    t.string "imprint"
    t.string "language"
    t.integer "page_count"
    t.string "printing"
    t.string "publish_date"
    t.string "publisher"
    t.datetime "updated_at", null: false
    t.bigint "variant_of_edition_id"
    t.index ["variant_of_edition_id"], name: "index_editions_on_variant_of_edition_id"
  end

  create_table "enrichment_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_type", null: false
    t.string "external_id", null: false
    t.datetime "fetched_at", null: false
    t.jsonb "fields", default: {}, null: false
    t.string "provider", null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["entity_type", "entity_id", "provider"], name: "index_enrichment_records_on_entity_and_provider", unique: true
  end

  create_table "genres", force: :cascade do |t|
    t.string "bisac_code"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "thema_code"
    t.datetime "updated_at", null: false
  end

  create_table "goodreads_sync_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "goodreads_book_id", null: false
    t.jsonb "last_synced_payload", default: {}, null: false
    t.string "shelf", null: false
    t.datetime "updated_at", null: false
    t.index ["goodreads_book_id", "shelf"], name: "index_goodreads_sync_states_on_goodreads_book_id_and_shelf", unique: true
  end

  create_table "job_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_type", null: false
    t.text "message"
    t.string "run_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["entity_type", "entity_id"], name: "index_job_items_on_entity"
    t.index ["run_id"], name: "index_job_items_on_run_id"
  end

  create_table "mobile_snapshots", force: :cascade do |t|
    t.bigint "byte_size"
    t.datetime "created_at", null: false
    t.integer "entry_count"
    t.datetime "generated_at"
    t.datetime "updated_at", null: false
    t.integer "version", default: 0, null: false
  end

  create_table "mobile_thumbs", id: false, force: :cascade do |t|
    t.string "blob_key", null: false
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "data", null: false
    t.index ["blob_key"], name: "index_mobile_thumbs_on_blob_key", unique: true
  end

  create_table "pending_decisions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "resolved_at"
    t.string "run_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["status"], name: "index_pending_decisions_on_status"
  end

  create_table "readings", force: :cascade do |t|
    t.bigint "copy_id"
    t.datetime "created_at", null: false
    t.date "date_finished"
    t.date "date_started"
    t.string "dnf_reason"
    t.bigint "edition_id", null: false
    t.text "private_notes"
    t.decimal "rating", precision: 3, scale: 1
    t.string "source"
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["copy_id"], name: "index_readings_on_copy_id"
    t.index ["edition_id"], name: "index_readings_on_edition_id"
    t.index ["work_id"], name: "index_readings_on_work_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.jsonb "channels", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "published_at"
    t.decimal "rating", precision: 3, scale: 1
    t.bigint "reading_id"
    t.string "status", default: "draft", null: false
    t.text "text"
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["reading_id"], name: "index_reviews_on_reading_id"
    t.index ["work_id"], name: "index_reviews_on_work_id"
  end

  create_table "series", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "field_sources", default: {}, null: false
    t.string "name", null: false
    t.string "status", default: "ongoing", null: false
    t.integer "total_count"
    t.datetime "updated_at", null: false
  end

  create_table "series_arcs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.decimal "position"
    t.bigint "series_id", null: false
    t.datetime "updated_at", null: false
    t.index ["series_id"], name: "index_series_arcs_on_series_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "storage_locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "parent_location_id"
    t.datetime "updated_at", null: false
    t.index ["parent_location_id"], name: "index_storage_locations_on_parent_location_id"
  end

  create_table "subjects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ddc_code"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_subjects_on_name", unique: true
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.datetime "created_at"
    t.string "event", null: false
    t.bigint "item_id", null: false
    t.string "item_type", null: false
    t.text "object"
    t.string "whodunnit"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  create_table "wishlist_items", force: :cascade do |t|
    t.string "author_name"
    t.string "cover_url"
    t.datetime "created_at", null: false
    t.jsonb "external_ids", default: {}, null: false
    t.text "notes"
    t.integer "priority"
    t.bigint "series_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id"
    t.index ["series_id"], name: "index_wishlist_items_on_series_id"
    t.index ["work_id"], name: "index_wishlist_items_on_work_id"
  end

  create_table "work_alternate_titles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "note"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["work_id"], name: "index_work_alternate_titles_on_work_id"
  end

  create_table "work_awards", force: :cascade do |t|
    t.bigint "award_id", null: false
    t.datetime "created_at", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.integer "year"
    t.index ["award_id"], name: "index_work_awards_on_award_id"
    t.index ["work_id"], name: "index_work_awards_on_work_id"
  end

  create_table "work_contributors", force: :cascade do |t|
    t.bigint "contributor_id", null: false
    t.datetime "created_at", null: false
    t.string "credited_as"
    t.integer "display_order"
    t.string "role"
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["contributor_id"], name: "index_work_contributors_on_contributor_id"
    t.index ["work_id"], name: "index_work_contributors_on_work_id"
  end

  create_table "work_genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "genre_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["genre_id"], name: "index_work_genres_on_genre_id"
    t.index ["work_id"], name: "index_work_genres_on_work_id"
  end

  create_table "work_series", force: :cascade do |t|
    t.bigint "arc_id"
    t.datetime "created_at", null: false
    t.decimal "position"
    t.bigint "series_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["arc_id"], name: "index_work_series_on_arc_id"
    t.index ["series_id"], name: "index_work_series_on_series_id"
    t.index ["work_id"], name: "index_work_series_on_work_id"
  end

  create_table "work_sibling_isbns", id: false, force: :cascade do |t|
    t.string "isbn13s", default: [], null: false, array: true
    t.string "queried_isbns", default: [], null: false, array: true
    t.datetime "refreshed_at", null: false
    t.bigint "work_id", null: false
    t.index ["work_id"], name: "index_work_sibling_isbns_on_work_id", unique: true
  end

  create_table "work_subjects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "subject_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["subject_id"], name: "index_work_subjects_on_subject_id"
    t.index ["work_id", "subject_id"], name: "index_work_subjects_on_work_id_and_subject_id", unique: true
    t.index ["work_id"], name: "index_work_subjects_on_work_id"
  end

  create_table "work_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "work_id", null: false
    t.index ["tag_id"], name: "index_work_tags_on_tag_id"
    t.index ["work_id"], name: "index_work_tags_on_work_id"
  end

  create_table "works", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "field_sources", default: {}, null: false
    t.string "literary_form", null: false
    t.text "notes"
    t.string "original_language"
    t.integer "original_publication_year"
    t.string "subtitle"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["title"], name: "index_works_on_title"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "copies", "editions"
  add_foreign_key "copies", "storage_locations"
  add_foreign_key "edition_contents", "editions"
  add_foreign_key "edition_contents", "works"
  add_foreign_key "edition_contributors", "contributors"
  add_foreign_key "edition_contributors", "editions"
  add_foreign_key "edition_identifiers", "editions"
  add_foreign_key "editions", "editions", column: "variant_of_edition_id"
  add_foreign_key "readings", "copies"
  add_foreign_key "readings", "editions"
  add_foreign_key "readings", "works"
  add_foreign_key "reviews", "readings"
  add_foreign_key "reviews", "works"
  add_foreign_key "series_arcs", "series"
  add_foreign_key "sessions", "users"
  add_foreign_key "storage_locations", "storage_locations", column: "parent_location_id"
  add_foreign_key "wishlist_items", "series"
  add_foreign_key "wishlist_items", "works"
  add_foreign_key "work_alternate_titles", "works"
  add_foreign_key "work_awards", "awards"
  add_foreign_key "work_awards", "works"
  add_foreign_key "work_contributors", "contributors"
  add_foreign_key "work_contributors", "works"
  add_foreign_key "work_genres", "genres"
  add_foreign_key "work_genres", "works"
  add_foreign_key "work_series", "series"
  add_foreign_key "work_series", "series_arcs", column: "arc_id"
  add_foreign_key "work_series", "works"
  add_foreign_key "work_subjects", "subjects"
  add_foreign_key "work_subjects", "works"
  add_foreign_key "work_tags", "tags"
  add_foreign_key "work_tags", "works"
end
