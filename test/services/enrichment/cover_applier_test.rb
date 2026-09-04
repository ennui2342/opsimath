require "test_helper"

module Enrichment
  class CoverApplierTest < ActiveSupport::TestCase
    # Stands in for Enrichment::CoverCompareClient — ratio: nil mirrors
    # what the real client returns when the sidecar is unreachable.
    # inliers defaults well above MIN_INLIERS so tests that only care
    # about the ratio threshold don't also have to think about the floor.
    FakeCompareClient = Struct.new(:ratio, :inliers, keyword_init: true) do
      def compare(*) = ratio && CoverCompareClient::Result.new(ratio: ratio, inliers: inliers || 500)
    end

    def attached_cover(bytes)
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(bytes), filename: "cover.jpg", content_type: "image/jpeg")
      edition.cover_image
    end

    test "plans a fill for a blank destination regardless of source" do
      edition = Edition.create!
      proposed = attached_cover("new-bytes")

      plan = CoverApplier.plan(edition, proposed, "goodreads")

      assert_equal :fill, plan.action
      assert_equal "goodreads", plan.source
    end

    test "plans unchanged when the proposed cover is byte-identical to what's already attached" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("same-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("same-bytes")

      plan = CoverApplier.plan(edition, proposed, "goodreads")

      assert_equal :unchanged, plan.action
    end

    test "plans a conflict when a populated destination genuinely differs — no per-source trust hierarchy" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("goodreads-bytes")

      plan = CoverApplier.plan(edition, proposed, "goodreads")

      assert_equal :conflict, plan.action
      assert_equal "goodreads", plan.source
    end

    test "plans unchanged when the compare sidecar scores the images as visually the same" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("goodreads-bytes-different-photo-same-cover")

      plan = CoverApplier.plan(edition, proposed, "goodreads", client: FakeCompareClient.new(ratio: 0.5))

      assert_equal :unchanged, plan.action
    end

    test "a high ratio with too few absolute inliers still plans a conflict — the ratio alone can be misleading on a near-blank image" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("goodreads-bytes")

      plan = CoverApplier.plan(edition, proposed, "goodreads", client: FakeCompareClient.new(ratio: 0.9, inliers: 10))

      assert_equal :conflict, plan.action
    end

    test "plans a conflict when the compare sidecar can't answer" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("goodreads-bytes")

      plan = CoverApplier.plan(edition, proposed, "goodreads", client: FakeCompareClient.new(ratio: nil))

      assert_equal :conflict, plan.action
    end

    test "authoritative: true fills on a genuine difference, bypassing the visual-compare gate entirely" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("isfdb-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("goodreads-bytes")
      spy_client = FakeCompareClient.new(ratio: 0.9) # would answer "same" if asked — asserting it's never asked

      plan = CoverApplier.plan(edition, proposed, "isfdb", authoritative: true, client: spy_client)

      assert_equal :fill, plan.action
      assert_equal "isfdb", plan.source
      assert_equal proposed.blob, plan.value
    end

    test "authoritative: true is still unchanged on a byte-identical cover — nothing to overwrite" do
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new("same-bytes"), filename: "old.jpg", content_type: "image/jpeg")
      proposed = attached_cover("same-bytes")

      plan = CoverApplier.plan(edition, proposed, "isfdb", authoritative: true)

      assert_equal :unchanged, plan.action
    end

    test "plans skipped when nothing is proposed" do
      edition = Edition.create!

      plan = CoverApplier.plan(edition, nil, "goodreads")

      assert_equal :skipped, plan.action
    end
  end
end
