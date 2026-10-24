# Bargain hunting (docs/BARGAIN_HUNTING.md).
namespace :bargains do
  desc "Fetch ISFDB printings (weekly per item) and author living/dead status (monthly) for wishlist items"
  task refresh_printings: :environment do
    puts WishlistPrintingRefreshJob.perform_now
  end

  desc "Report what the collecting profile wants, per wishlist book (★ = favourite artist). " \
       "TITLE filters by title; RULE by rule (a_format, buy_new, …); SUMMARY=1 prints only the totals"
  task printings: :environment do
    profile = CollectingProfile.current
    favourites = profile.favourite_artists.to_set
    items = WishlistItem.includes(:wishlist_printings).order(:title)
    items = items.where("title ILIKE ?", "%#{ENV['TITLE']}%") if ENV["TITLE"]

    totals = Hash.new(0)
    favourite_wanted = 0
    items.each do |item|
      printings = item.wishlist_printings.sort_by { |p| [ p.year || 9999, p.publish_date.to_s ] }
      verdict = profile.verdict(item, printings)
      totals[verdict.rule] += 1
      favourite_wanted += verdict.wanted.count { |p| (p.artists & favourites.to_a).any? }
      next if ENV["SUMMARY"] || (ENV["RULE"] && verdict.rule.to_s != ENV["RULE"])

      author = item.author_status == :dead ? "d. #{item.author_died_date[0, 4]}" : item.author_status
      puts "\n#{item.title} — #{item.author_name} (#{author})  [#{verdict.rule}, first #{verdict.first_year || '?'}, " \
           "#{verdict.wanted.size}/#{printings.size} wanted]"
      printings.each do |p|
        mark = verdict.wanted?(p) ? "✓" : " "
        star = (p.artists & favourites.to_a).any? ? "★" : " "
        puts format("  %s%s %-10s %-4s %-32s %-28s %s", mark, star, p.publish_date || "undated", p.binding,
                    p.publisher.to_s.truncate(32), p.cover_artist.to_s.truncate(28), p.isbn13 || p.isbn10 || "no ISBN")
      end
    end

    puts "\nbuy new: no A-format and first published in the last #{profile.recent_years} years or author living/unknown"
    puts "favourite artists: #{favourites.size} (owned >= #{profile.favourite_artist_min_owned}, " \
         "+#{profile.favourite_artists_always.size} always, -#{profile.favourite_artists_never.size} never)"
    totals.sort_by { |_, n| -n }.each { |rule, n| puts "  #{rule}: #{n}" }
    puts "  wanted printings by a favourite artist: #{favourite_wanted}"
  end
end

namespace :bargains do
  desc "Search eBay for hunted wishlist books, then identify a batch of new listings' printings"
  task sweep: :environment do
    puts EbaySweepJob.perform_now
  end

  desc "Identify printings for up to LIMIT (default 1000) unidentified listings, cheapest first"
  task identify: :environment do
    puts Ebay::PrintingIdentifier.run(limit: Integer(ENV.fetch("LIMIT", Ebay::PrintingIdentifier::BATCH)))
  end

  desc "Report live eBay listings per hunted book, grouped by identified printing " \
       "(✓ wanted, ★ favourite artist). TITLE filters; SUMMARY=1 prints only the totals"
  task finds: :environment do
    profile = CollectingProfile.current
    favourites = profile.favourite_artists
    gbp = ->(pence) { pence ? format("£%.2f", pence / 100.0) : "?" }
    items = WishlistItem.includes(:wishlist_printings, :ebay_listings).order(:title)
    items = items.where("title ILIKE ?", "%#{ENV['TITLE']}%") if ENV["TITLE"]

    items.each do |item|
      listings = item.ebay_listings.select { |l| l.ended_at.nil? }
      next if ENV["SUMMARY"] || listings.empty?

      verdict = profile.verdict(item)
      puts "\n#{item.title} — #{item.author_name}  [#{verdict.rule}, #{listings.size} live]"
      listings.group_by(&:matched_pub_ids).sort_by { |ids, _| ids.empty? ? 1 : 0 }.each do |ids, group|
        printings = item.wishlist_printings.select { |p| ids.include?(p.isfdb_pub_id) }
        label =
          if group.first.identified_by.nil? then "not identified yet"
          elsif printings.empty? then "printing unknown"
          else printings.map { |p| "#{p.publisher} #{p.binding} #{p.publish_date || 'undated'}" }.uniq.first(3).join("; ")
          end
        wanted = printings.any? { |p| verdict.wanted?(p) } ? "✓" : " "
        star = printings.any? { |p| (p.artists & favourites).any? } ? "★" : " "
        cheapest = group.min_by { |l| l.total || Float::INFINITY }
        puts format("  %s%s %-60s %3d listing(s), from %s (%s)", wanted, star, label.truncate(60), group.size,
                    gbp.(cheapest.total), group.map(&:identified_by).compact.tally.map { |k, v| "#{k} #{v}" }.join(", "))
      end
    end

    live = EbayListing.live
    puts "\nlive listings: #{live.count} across #{live.distinct.count(:wishlist_item_id)} books; " \
         "identified by: #{live.group(:identified_by).count.transform_keys { |k| k || 'not yet' }}"
  end
end
