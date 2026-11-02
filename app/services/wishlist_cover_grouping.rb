# Groups each hunted wishlist book's printings — its work's physical ISFDB
# editions (Want#printings) — by cover art: the unit Mark picks covers in,
# and prices are compared in (docs/BARGAIN_HUNTING.md). Stored as
# ProviderEdition#cover_group: the representative printing's pub id, shared
# by every printing with the same cover.
#
# Within one binding only: the picker shows one format per book, so an
# A-format and a B-format sharing a painting don't need to be one group.
# Greedy, earliest printing first: each cover is compared with one
# representative per existing group, not with every other cover (the
# biggest wishlist book has 73 distinct ISFDB covers). Printings sharing
# a cover URL group without a comparison; one with no cover is a group of
# its own.
#
# A book is regrouped only when its printings change (Want#cover_groups_digest),
# so after the first run this is a few new books a day. Bounded by a
# wall-clock deadline; books not reached keep their old digest and are
# picked up next run.
class WishlistCoverGrouping
  DEADLINE = 30.minutes

  Result = Struct.new(:hunted, :stale, :grouped, :comparisons, :truncated, keyword_init: true) do
    def to_s = "hunted=#{hunted} stale=#{stale} grouped=#{grouped} comparisons=#{comparisons}#{' TRUNCATED' if truncated}"
  end

  def self.run(**) = new(**).run

  def initialize(compare: Enrichment::CoverCompareClient.new, profile: CollectingProfile.current, deadline: DEADLINE)
    @compare = compare
    @profile = profile
    @deadline = deadline
  end

  def run(wants = Want.includes(work: [ :provider_editions, { work_contributors: :contributor } ]))
    started = Time.current
    result = Result.new(hunted: 0, stale: 0, grouped: 0, comparisons: 0, truncated: false)
    wants.each do |want|
      next unless @profile.verdict(want).hunt?

      result.hunted += 1
      digest = self.class.digest(want.printings)
      next if want.cover_groups_digest == digest

      result.stale += 1
      if Time.current - started > @deadline
        result.truncated = true
        next
      end
      result.comparisons += group(want)
      want.update_columns(cover_groups_digest: digest)
      result.grouped += 1
    end
    result
  end

  def self.digest(printings)
    Digest::SHA1.hexdigest(printings.map { |p| [ p.isfdb_pub_id, p.binding, p.cover_url ] }.sort_by(&:first).to_json)
  end

  private

  # -> number of cover comparisons made
  def group(want)
    images = {}
    comparisons = 0
    want.printings.group_by(&:binding).each_value do |printings|
      reps = [] # [representative printing, its image bytes]
      printings.sort_by { |p| [ p.year || 9999, p.isfdb_pub_id ] }.each do |p|
        rep = reps.find { |r, _| p.cover_url.present? && r.cover_url == p.cover_url }
        if rep.nil? && (bytes = image(images, p.cover_url))
          rep = reps.find do |_, rep_bytes|
            next false unless rep_bytes

            comparisons += 1
            (result = @compare.compare(bytes, rep_bytes)) && CoverMatch.same?(result.ratio, result.inliers)
          end
        end
        if rep
          p.update_columns(cover_group: rep.first.provider_id)
        else
          reps << [ p, image(images, p.cover_url) ]
          p.update_columns(cover_group: p.provider_id)
        end
      end
    end
    comparisons
  end

  def image(cache, url)
    return if url.blank?

    cache.fetch(url) { cache[url] = HasCoverImage.fetch_image(url)&.dig(:io)&.read }
  end
end
