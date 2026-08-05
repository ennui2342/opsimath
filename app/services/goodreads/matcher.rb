module Goodreads
  # Resolves a Goodreads::RssClient::FeedItem to an existing catalog Work/
  # Edition, if one exists. Three tiers, tried in order, per
  # docs/INTEGRATIONS.md's matching strategy:
  #
  # 1. `goodreads_book_id` against `EditionIdentifier(id_type: "goodreads")`
  #    — exact, since Phase 1 already tagged every CSV-imported book this
  #    way (1,985 rows). Covers most shelf-transition events.
  # 2. `isbn` against `EditionIdentifier(id_type: "isbn10")` — the feed
  #    never provides isbn13 (confirmed against the real live feed), only
  #    isbn10.
  # 3. Exact normalized title+author, ported from
  #    `Goodreads::Importer#find_or_create_work`'s own lookup — the
  #    fallback for a book Phase 1 never saw (a genuinely new addition) or
  #    one whose Goodreads catalog id churned since import.
  #
  # Returns nil (no match — safe to auto-create) when nothing matches at
  # all. Returns a Result with `ambiguous: true` when tier 3 matches more
  # than one Work — genuinely can't tell which one without a human,
  # doesn't guess.
  class Matcher
    Result = Struct.new(:work, :edition, :ambiguous, keyword_init: true)

    def self.match(item)
      new(item).match
    end

    def initialize(item)
      @item = item
    end

    def match
      by_goodreads_id || by_isbn || by_title_author
    end

    private

    def by_goodreads_id
      edition_for(EditionIdentifier.find_by(id_type: "goodreads", value: @item.goodreads_book_id))
    end

    def by_isbn
      return nil if @item.isbn.blank?

      edition_for(EditionIdentifier.find_by(id_type: "isbn10", value: @item.isbn))
    end

    def edition_for(identifier)
      return nil unless identifier

      edition = Edition.find(identifier.edition_id)
      Result.new(work: edition.works.first, edition: edition, ambiguous: false)
    end

    def by_title_author
      info = RowParser.series_info(@item.title)
      author = RowParser.clean_name(@item.author_name)

      works = Work.joins(work_contributors: :contributor)
                  .where("lower(works.title) = ?", info.title.downcase)
                  .where(work_contributors: { role: "author" })
                  .where("lower(contributors.name) = ?", author.to_s.downcase)
                  .distinct.to_a
      return nil if works.empty?
      return Result.new(work: nil, edition: nil, ambiguous: true) if works.size > 1

      work = works.first
      Result.new(work: work, edition: work.editions.first, ambiguous: false)
    end
  end
end
