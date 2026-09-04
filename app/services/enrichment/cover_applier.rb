module Enrichment
  # The cover_image equivalent of FieldApplier.plan — an attachment can't
  # go through FieldApplier.plan directly (no plain #public_send/
  # #normalize-style column comparison applies), but this returns the
  # same FieldApplier::Plan shape so a cover plan sits alongside every
  # other field's plan identically wherever a caller collects them for
  # Enrichment::SourceRecorder.integrate. Pure planning only, same as
  # FieldApplier — nothing here commits anything.
  #
  # Deliberately naive on bytes: a blank destination always fills,
  # regardless of source; a populated destination with matching bytes is
  # unchanged. Mark, 2026-08-08: "covers only fill in on nil regardless
  # of source, otherwise there's a conflict" — no per-provider trust
  # hierarchy. A populated destination with *differing* bytes is no
  # longer an automatic conflict, though: before proposing one, it asks
  # the cover-compare sidecar (services/cover_compare/) whether the two
  # images are actually the same physical cover under different lighting/
  # crop/framing — validated empirically (2026-08-08 eval, then a live
  # 28-pair spot-check from a real sync run) that byte-exact comparison
  # alone produces a lot of false conflicts once a second source starts
  # proposing covers against editions ISFDB already populated.
  #
  # Requires BOTH a ratio and an absolute inlier-count floor, not ratio
  # alone: the live spot-check found a real case (a busy, detailed cover)
  # where a confident match — 301 RANSAC inliers, an 86% survival rate
  # against its candidate matches — still reported a low ratio, purely
  # because the ratio divides by the smaller image's *total* keypoint
  # count, and a richly-detailed cover has a lot of keypoints regardless
  # of how many of them actually matched. MIN_INLIERS is a floor against
  # the opposite failure — a near-blank image with very few keypoints at
  # all can post a misleadingly high ratio from a handful of coincidental
  # matches — set between the two clusters actually observed in that
  # spot-check (post cover-compare's scale normalization): every genuine
  # match cleared at 412+ inliers, while the one confirmed genuine
  # conflict in the batch (same illustration, a real differing
  # contributor-list region) still posted 277 — a real, close case ratio
  # alone also correctly excludes, but the floor is set to reject it on
  # this signal too rather than resting on only one of the two.
  # SAME_THRESHOLD sits comfortably above the observed "real printed
  # difference" ceiling and comfortably below most confirmed "same photo"
  # scores — genuinely ambiguous or lower-confidence cases still fall
  # through to a real conflict, same as the sidecar being unreachable does.
  #
  # `authoritative: true` skips all of the above and always fills on a
  # byte difference — for a caller that has already confidently resolved
  # *which specific printing* this cover belongs to, not just "a cover
  # from a source we trust." IsfdbEditionEnricher is the one caller that
  # can say that: its own `enrich` only ever reaches this method after
  # #resolve_candidate has picked exactly one ISFDB pub for the edition's
  # ISBN (never a guess among several reprints — that case raises
  # enrichment_printing_choice instead and never calls this at all). At
  # that point a differing cover isn't a candidate ambiguity to sanity-
  # check — it's simply this printing's real cover, which should win
  # outright over whatever's attached (often a Goodreads user's photo of
  # a different printing, or no cover at all). Mark, 2026-09-04: "be more
  # relaxed about auto-accepting an ISBN-matched ISFDB cover" — the
  # per-edition cog + right-click cover picker (docs/DESIGN_SYSTEM.md)
  # was built first as the manual fix path for when this trust turns out
  # to be wrong. Goodreads (no per-printing resolution to anchor on)
  # keeps the full gate.
  module CoverApplier
    SAME_THRESHOLD = 0.2
    MIN_INLIERS = 350

    def self.plan(record, proposed, source, authoritative: false, client: CoverCompareClient.new)
      return FieldApplier::Plan.new(action: :skipped) unless proposed&.attached?
      return FieldApplier::Plan.new(record: record, field: :cover_image, action: :fill, value: proposed.blob, source: source) unless record.cover_image.attached?
      return FieldApplier::Plan.new(action: :unchanged) if proposed.blob.checksum == record.cover_image.blob.checksum
      return FieldApplier::Plan.new(record: record, field: :cover_image, action: :fill, value: proposed.blob, source: source) if authoritative
      return FieldApplier::Plan.new(action: :unchanged) if visually_same?(record.cover_image, proposed, client)

      FieldApplier::Plan.new(record: record, field: :cover_image, action: :conflict, source: source)
    end

    def self.visually_same?(current, proposed, client)
      result = client.compare(current.download, proposed.download)
      result && result.ratio >= SAME_THRESHOLD && result.inliers >= MIN_INLIERS
    end
    private_class_method :visually_same?
  end
end
