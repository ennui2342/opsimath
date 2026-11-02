# Everything the wishlist book page shows (docs/BARGAIN_HUNTING.md, "Front
# end"): the covers Mark can choose between — the rule's candidate
# printings, one choice per cover group — whether each is chosen, and
# the live eBay listings sorted onto them, cheapest first. Listings that
# aren't on any offered cover (another format, printing unknown, not yet
# identified) are kept apart for an eyeball check.
class WishlistItemView
  # `listings`: what's shown — live, not dismissed, cheapest first.
  # `priced`: the cover's market — live listings including dismissed ones,
  # whose prices are still what the cover sells for (Finds' median).
  Cover = Struct.new(:id, :printings, :artists, :favourite, :chosen, :listings, :priced, keyword_init: true) do
    def cover_url = printings.filter_map(&:cover_url).first

    def first_year = printings.filter_map(&:year).min

    # "Orbit 1979, 1985" — publishers in order, each with its years.
    def summary
      printings.sort_by { |p| p.year || 9999 }.group_by { |p| p.publisher.to_s.split(" / ").first.presence || "?" }
               .map { |pub, ps| "#{pub} #{ps.map { |p| p.year || 'undated' }.uniq.join(', ')}" }.join(" · ")
    end

    def cheapest = listings.first

    def priced = self[:priced] || listings
  end

  attr_reader :want, :verdict, :rule

  def initialize(want, profile: CollectingProfile.current)
    @want = want
    @profile = profile
    printings = want.printings
    @rule = profile.verdict(want, printings, ignore_override: true)
    @verdict = profile.verdict(want, printings)
    @favourites = profile.favourite_artists
    @market = want.work.ebay_listings.select { |l| l.ended_at.nil? && %w[new dismissed].include?(l.status) }
                    .sort_by { |l| l.total || Float::INFINITY }
    @live = @market.select { |l| l.status == "new" }
  end

  def hunted? = verdict.hunt?

  def overridden? = !want.printing_override_ids.nil?

  def covers
    @covers ||= rule.wanted.group_by { |p| p.cover_group&.to_i || p.isfdb_pub_id }.map do |id, printings|
      ids = printings.map(&:isfdb_pub_id)
      artists = printings.flat_map(&:artists).uniq
      Cover.new(id:, printings:, artists:, favourite: (artists & @favourites).any?,
                chosen: printings.any? { |p| verdict.wanted?(p) },
                listings: @live.select { |l| (l.matched_pub_ids & ids).any? },
                priced: @market.select { |l| (l.matched_pub_ids & ids).any? })
    end.sort_by { |c| [ c.first_year || 9999, c.id ] }
  end

  # Live listings on none of the offered covers, by why: :other_printing
  # (identified, but a format or printing the rule doesn't offer),
  # :unknown (couldn't be identified), :pending (not tried yet).
  def other_listings
    offered = covers.flat_map(&:listings).to_set
    @live.reject { |l| offered.include?(l) }.group_by do |l|
      if l.identified_by.nil? then :pending
      elsif l.matched_pub_ids.empty? then :unknown
      else :other_printing
      end
    end
  end

  # Printing override for the chosen cover ids: every candidate printing
  # on a chosen cover — or nil when every cover is chosen, so the rule's
  # default stays in charge and new printings keep arriving.
  def self.override_for(view, chosen_ids)
    chosen = view.covers.select { |c| chosen_ids.include?(c.id) }
    return nil if chosen.size == view.covers.size

    chosen.flat_map { |c| c.printings.map(&:isfdb_pub_id) }
  end
end
