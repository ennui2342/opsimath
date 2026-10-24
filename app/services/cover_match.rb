# When two cover images count as the same cover art, for bargain hunting
# (docs/BARGAIN_HUNTING.md): an eBay listing photo against an ISFDB scan
# (Ebay::PrintingIdentifier), and two ISFDB scans of different printings
# (WishlistCoverGrouping).
#
# Looser than Enrichment::CoverApplier's 0.2 / 350, which decides whether
# two clean scans are interchangeable *images*. Here the question is the
# *art*: a phone photo of a real copy scores lower than a scan, and a
# reprint with the same painting but reset type should still count as the
# same cover. Different covers score under ~0.01 (the cover-compare eval);
# chosen in the 138-listing spike, to be tuned against Mark's corrections.
module CoverMatch
  SAME_RATIO = 0.08
  MIN_INLIERS = 30

  def self.same?(ratio, inliers) = ratio.to_f >= SAME_RATIO && inliers.to_i >= MIN_INLIERS
end
