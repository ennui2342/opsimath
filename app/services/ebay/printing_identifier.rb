module Ebay
  # Works out which printing(s) of a wishlist book an eBay listing is
  # (docs/BARGAIN_HUNTING.md, "Identify the printing"). The photo is the
  # main evidence: older printings share ISBNs across reprints with
  # different covers, and sellers attach a catalogue ISBN whatever copy
  # they have, but the photo shows the copy being sold.
  #
  # 1. Cover: the listing photo against each printing's ISFDB cover, via
  #    the cover-compare sidecar. The best-scoring printing, plus any
  #    within TIE_MARGIN of it (printings sharing the cover art), if it
  #    scores as the same cover at all.
  # 2. Text: an ISBN, or a publisher + year, in the listing title — used
  #    alone when no cover matched, and to narrow a shared-cover group
  #    when it can. Never to overrule a cover match.
  # 3. Otherwise unknown.
  #
  # "Same cover" is CoverMatch's threshold.
  class PrintingIdentifier
    TIE_MARGIN = 0.03
    BATCH = 1000 # ~1.1s each (one cover-compare call per distinct cover): ~18 min a night
    # Dropped from a publisher name before looking for it in a listing
    # title: sellers write "Pan", ISFDB has "Pan Books".
    GENERIC_PUBLISHER_WORDS = %w[books book publishing publishers press paperbacks paperback ltd inc the co].freeze

    Result = Struct.new(:identified, :by, keyword_init: true) do
      def to_s = "identified=#{identified} #{by.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    end

    # Identify up to `limit` live, not-yet-identified listings, cheapest
    # first — a first sweep finds thousands, and the cheap ones are the
    # ones that matter.
    def self.run(limit: BATCH, **)
      identifier = new(**)
      listings = EbayListing.live.unidentified.includes(wishlist_item: :wishlist_printings).order(:price).limit(limit)
      by = Hash.new(0)
      listings.each { |listing| by[identifier.identify(listing)] += 1 }
      Result.new(identified: by.values.sum, by:)
    end

    def initialize(compare: Enrichment::CoverCompareClient.new)
      @compare = compare
      @covers = {} # cover_url -> bytes, for the run
    end

    # Identifies and saves one listing; returns how ("cover"/"text"/"unknown").
    def identify(listing)
      printings = listing.wishlist_item.wishlist_printings.to_a
      scores = cover_scores(listing, printings)
      matched, by = by_cover(printings, scores)
      if matched.any?
        narrowed = by_text(listing.title, matched)
        matched = narrowed if narrowed.any?
      else
        matched = by_text(listing.title, printings)
        by = matched.any? ? "text" : "unknown"
      end

      listing.update!(matched_pub_ids: matched.map(&:isfdb_pub_id), identified_by: by,
                      cover_scores: scores.transform_keys(&:to_s))
      by
    end

    private

    # {isfdb_pub_id => {"ratio", "inliers"}} for every printing with a
    # cover. Each distinct cover image is compared once (ISFDB often
    # reuses one scan across printings).
    def cover_scores(listing, printings)
      photo = image(listing.image_url)
      return {} unless photo

      by_url = {}
      printings.select { |p| p.cover_url.present? }.each_with_object({}) do |p, scores|
        result = by_url.fetch(p.cover_url) { by_url[p.cover_url] = (cover = image(p.cover_url)) && @compare.compare(photo, cover) }
        scores[p.isfdb_pub_id] = { "ratio" => result.ratio, "inliers" => result.inliers } if result
      end
    end

    def by_cover(printings, scores)
      same = printings.select do |p|
        s = scores[p.isfdb_pub_id]
        s && CoverMatch.same?(s["ratio"], s["inliers"])
      end
      return [ [], nil ] if same.empty?

      best = same.map { |p| scores[p.isfdb_pub_id]["ratio"] }.max
      [ same.select { |p| best - scores[p.isfdb_pub_id]["ratio"] <= TIE_MARGIN }, "cover" ]
    end

    # Printings the listing title pins down: those sharing an ISBN it
    # quotes, else the one printing whose publisher (and year, if the
    # title gives one) it names. [] when the text doesn't settle it.
    def by_text(title, printings)
      isbns = title.scan(/\b97[89][\d-]{10,14}\b|\b\d{9}[\dXx]\b/).map { |raw| to13(raw.delete("-")) }.compact
      if isbns.any?
        hits = printings.select { |p| (isbns & [ p.isbn13, to13(p.isbn10) ].compact).any? }
        return hits if hits.any?
      end

      words = " #{fold(title)} "
      years = title.scan(/\b(?:19|20)\d\d\b/).map(&:to_i)
      hits = printings.select do |p|
        name = publisher_core(p.publisher)
        name.length >= 3 && words.include?(" #{name} ") && (years.empty? || years.include?(p.year))
      end
      hits.one? ? hits : []
    end

    # "Panther / Granada" -> "panther", "Pan Books" -> "pan".
    def publisher_core(publisher)
      (fold(publisher.to_s.split(" / ").first).split - GENERIC_PUBLISHER_WORDS).join(" ")
    end

    def fold(text) = I18n.transliterate(text.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip

    def to13(isbn)
      return if isbn.blank?

      isbn.length == 13 ? isbn : Isbn.to_13(isbn)
    end

    def image(url)
      return if url.blank?

      @covers.fetch(url) { @covers[url] = HasCoverImage.fetch_image(url)&.dig(:io)&.read }
    end
  end
end
