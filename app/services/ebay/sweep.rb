module Ebay
  # Searches eBay UK for every wishlist book the collecting profile says
  # to hunt, and records what it finds as EbayListing rows
  # (docs/BARGAIN_HUNTING.md, "Search"). Two calls per book:
  #
  # - keywords — "<short title> <author>", Books category, UK sellers,
  #   cheapest first, so the 50-result page drops the expensive copies,
  #   never the bargains;
  # - the ISBN the book was wishlisted under, as a cross-check.
  #
  # Listings are filtered to the right book (author surname and the
  # title's opening words in the listing title; no job lots or bundles)
  # and upserted. Identifying the printing is Ebay::PrintingIdentifier's
  # job, run afterwards.
  #
  # A live listing not seen for ENDED_AFTER is marked ended. Absence from
  # one search proves nothing — an expensive copy can drop off the end of
  # a cheapest-first page — so only a past auction end time ends a
  # listing sooner.
  class Sweep
    BOOKS_CATEGORY = "267".freeze # Books, Comics & Magazines
    # Job lots, and the study guides that share a classic's title.
    JUNK = /\b(#{[
      'job ?lot', 'bundle', 'lot of', 'set of', '\d+\s*books', 'collection of', 'x\s*\d+\s*books',
      'york notes', 'study (guide|texts?)', 'cliffs ?notes', 'spark ?notes', 'coles notes', 'workbook',
      'summary of', 'analysis of'
    ].join('|')})\b/i
    EXCLUDED_CONDITIONS = [ "For parts or not working" ].freeze
    ENDED_AFTER = 7.days
    TITLE_WORDS = 3

    Result = Struct.new(:hunted, :searches, :seen, :created, :ended, :failed, keyword_init: true) do
      def to_s = "hunted=#{hunted} searches=#{searches} seen=#{seen} new=#{created} ended=#{ended} failed=#{failed}"
    end

    def self.run(**) = new(**).run

    def initialize(client: Client.new, profile: CollectingProfile.current, now: Time.current)
      @client = client
      @profile = profile
      @now = now
    end

    def run(items = WishlistItem.includes(:wishlist_printings))
      result = Result.new(hunted: 0, searches: 0, seen: 0, created: 0, ended: 0, failed: 0)
      items.each do |item|
        next unless @profile.verdict(item).hunt?

        result.hunted += 1
        sweep(item, result)
      rescue Error => e
        result.failed += 1
        Rails.logger.warn("eBay sweep: item ##{item.id} — #{e.message}")
      end
      result.ended = end_stale_listings
      result
    end

    private

    def sweep(item, result)
      found = keyword_search(item).map { |s| [ s, "keyword" ] }
      result.searches += 1
      if (isbn = isbn13(item))
        found += @client.search(gtin: isbn).map { |s| [ s, "gtin" ] }
        result.searches += 1
      end

      found.uniq { |summary, _| summary["itemId"] }.each do |summary, found_by|
        next unless relevant?(item, summary)

        result.seen += 1
        result.created += 1 if record(item, summary, found_by)
      end
    end

    def keyword_search(item)
      @client.search(q: "#{short_title(item.title)} #{item.author_name}", category_ids: BOOKS_CATEGORY,
                     filter: "itemLocationCountry:GB", sort: "price")
    end

    def relevant?(item, summary)
      title = summary["title"].to_s
      return false if title.match?(JUNK) || EXCLUDED_CONDITIONS.include?(summary["condition"])

      words = " #{fold(title)} "
      surname = fold(item.author_name.to_s.sub(/,?\s+(jr|sr)\.?\z/i, "")).split.last
      opening = fold(short_title(item.title)).split.first(TITLE_WORDS).join(" ")
      words.include?(" #{opening} ") && (surname.nil? || words.include?(" #{surname} "))
    end

    # -> true when the listing is new.
    def record(item, summary, found_by)
      listing = item.ebay_listings.find_or_initialize_by(ebay_item_id: summary["itemId"])
      created = listing.new_record?
      listing.assign_attributes(attributes(summary).merge(last_seen_at: @now, ended_at: nil))
      listing.first_seen_at ||= @now
      listing.found_by ||= found_by
      listing.save!
      created
    end

    def attributes(summary)
      shipping = Array(summary["shippingOptions"]).first
      {
        title: summary["title"],
        url: summary["itemWebUrl"],
        image_url: Array(summary["thumbnailImages"]).first&.dig("imageUrl") || summary.dig("image", "imageUrl"),
        price: pence(summary["price"]),
        current_bid: pence(summary["currentBidPrice"]),
        shipping: pence(shipping&.dig("shippingCost")),
        shipping_type: shipping&.dig("shippingCostType"),
        original_currency: summary.dig("price", "convertedFromCurrency"),
        condition: summary["condition"],
        buying_options: Array(summary["buyingOptions"]),
        auction_ends_at: summary["itemEndDate"],
        bid_count: summary["bidCount"],
        seller_country: summary.dig("itemLocation", "country")
      }
    end

    def end_stale_listings
      EbayListing.live.where("last_seen_at < ? OR auction_ends_at < ?", @now - ENDED_AFTER, @now)
                 .update_all(ended_at: @now)
    end

    def pence(amount)
      amount && (BigDecimal(amount["value"]) * 100).round
    end

    def isbn13(item)
      item.external_ids["isbn13"].presence || (item.external_ids["isbn10"].presence && Isbn.to_13(item.external_ids["isbn10"]))
    end

    # The title up to any subtitle or series suffix: "World's Edge: A
    # Mosaic Novel" -> "World's Edge".
    def short_title(title) = title.split(/[:(]/).first.strip

    # Lower-case ASCII words, punctuation dropped — so "Hello Summer,
    # Goodbye" and "Cortázar" compare as listing titles write them.
    def fold(text) = I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
