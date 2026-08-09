require "test_helper"

class EnrichmentRecordTest < ActiveSupport::TestCase
  test "only one record is allowed per (entity, provider) — a second create! for the same pair is invalid" do
    edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {})

    duplicate = EnrichmentRecord.new(entity: edition, provider: "goodreads", external_id: "2", fetched_at: Time.current, raw_payload: {})

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:provider], "has already been taken"
  end

  test "a different provider for the same entity, or the same provider for a different entity, is unaffected" do
    edition = Edition.create!
    other_edition = Edition.create!
    EnrichmentRecord.create!(entity: edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {})

    assert EnrichmentRecord.new(entity: edition, provider: "isfdb", external_id: "2", fetched_at: Time.current, raw_payload: {}).valid?
    assert EnrichmentRecord.new(entity: other_edition, provider: "goodreads", external_id: "1", fetched_at: Time.current, raw_payload: {}).valid?
  end

  test ".latest finds the single record for an (entity, provider) pair" do
    edition = Edition.create!
    record = EnrichmentRecord.create!(entity: edition, provider: "isfdb", external_id: "1", fetched_at: Time.current, raw_payload: {})

    assert_equal record, EnrichmentRecord.latest(entity: edition, provider: "isfdb")
  end

  test ".latest is nil when this provider has never touched the entity" do
    edition = Edition.create!

    assert_nil EnrichmentRecord.latest(entity: edition, provider: "isfdb")
  end
end
