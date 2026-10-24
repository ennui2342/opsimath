# The daily Discord message of new eBay finds (docs/BARGAIN_HUNTING.md,
# "Report"), sent after the nightly sweep: one line per find not yet
# announced — book, cover artist (★ favourite), delivered price, why it's
# a find, a link to the listing — and a link to /finds to act on them.
# Each listing is announced once (EbayListing#notified_at); nothing is
# sent when there's nothing new.
class FindsDigest
  MAX_LINES = 25 # the rest are on /finds; Discord caps the message anyway

  def self.run(finds: Finds.all, now: Time.current)
    fresh = finds.reject { |f| f.listing.notified_at }
    return 0 if fresh.empty?

    Notifications.notify(Notifications::Event.new(
      kind: :ebay_finds, level: :info,
      title: "eBay: #{fresh.size} new #{'find'.pluralize(fresh.size)}",
      url: "#{Rails.application.config.x.public_url}/finds",
      description: description(fresh),
      fields: {}
    ))
    EbayListing.where(id: fresh.map { |f| f.listing.id }).update_all(notified_at: now)
    fresh.size
  end

  def self.description(finds)
    lines = finds.first(MAX_LINES).map { |f| line(f) }
    lines << "…and #{finds.size - MAX_LINES} more" if finds.size > MAX_LINES
    lines.join("\n")
  end

  def self.line(find)
    star = find.favourite? ? "★ " : ""
    artist = find.cover.artists.first || "cover artist unknown"
    why = find.reason == :target ? "under your #{gbp(find.item.target_price)} target" : "#{(find.ratio * 100).round}% of usual #{gbp(find.median.round)}"
    ending = find.listing.auction? && find.listing.auction_ends_at ? ", auction ends #{find.listing.auction_ends_at.strftime('%a %H:%M')}" : ""
    "#{star}**#{find.item.title}** — #{artist} · #{gbp(find.listing.total)} (#{why}#{ending}) · [eBay](#{short_url(find.listing.link)})"
  end

  # eBay's item URLs carry search-tracking parameters; the item path is
  # enough, and Discord's description limit is better spent on finds.
  def self.short_url(url) = url.to_s.split("?").first

  def self.gbp(pence) = format("£%.2f", pence / 100.0)
end
