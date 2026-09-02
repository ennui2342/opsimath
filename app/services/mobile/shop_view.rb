module Mobile
  # The denormalised "shop view" of the collection: one row per catalogued
  # work you own or have wishlisted, plus a row per wishlist entry not yet
  # matched to a work. Everything the offline lookup PWA needs to answer
  # "owned / wishlisted / neither" for a book in hand (docs/MOBILE.md
  # constraint 3).
  #
  # Format-agnostic plain data — Mobile::SnapshotBuilder turns it into
  # snapshot.sqlite3; the same shape is the natural basis for a public API
  # if one is ever wanted. "Do I own an edition of this work" and "is this
  # work wishlisted" each resolve in one query, not a per-work check.
  class ShopView
    Work = Struct.new(
      :id, :title, :subtitle, :authors, :series, :series_position,
      :original_year, :owned, :wishlisted, :editions, keyword_init: true
    )
    Edition = Struct.new(
      :id, :format, :format_detail, :publisher, :year, :isbn10, :isbn13, :has_cover,
      keyword_init: true
    )
    WishlistEntry = Struct.new(
      :id, :title, :author, :series, :isbn10, :isbn13, :has_cover, keyword_init: true
    )
    Result = Struct.new(:works, :wishlist_entries, keyword_init: true)

    def self.build = new.build

    def build
      Result.new(works: work_rows, wishlist_entries: wishlist_rows)
    end

    private

    def work_rows
      owned = owned_work_ids
      wishlisted = wishlisted_work_ids

      scope
        .where(id: owned | wishlisted)
        .find_each
        .map { |work| build_work(work, owned:, wishlisted:) }
        .sort_by { |w| w.title.to_s.downcase }
    end

    def scope
      ::Work.includes(
        { work_contributors: :contributor },
        { work_series: :series },
        { editions: [ :edition_identifiers, :copies, { cover_image_attachment: :blob } ] }
      )
    end

    def build_work(work, owned:, wishlisted:)
      first_series = work.work_series.min_by { |ws| ws.position || Float::INFINITY }

      Work.new(
        id: work.id,
        title: work.title,
        subtitle: work.subtitle.presence,
        authors: authors_of(work),
        series: first_series&.series&.name,
        series_position: first_series&.position && format("%g", first_series.position),
        original_year: work.original_publication_year,
        owned: owned.include?(work.id),
        wishlisted: wishlisted.include?(work.id),
        editions: owned_editions_of(work)
      )
    end

    def authors_of(work)
      work.work_contributors
          .select { |wc| wc.role == "author" }
          .sort_by { |wc| wc.display_order || Float::INFINITY }
          .map { |wc| wc.contributor.name }
    end

    # Only the editions you actually own a copy of — that's what's useful
    # in a shop ("you own the mass-market, Ace, 1984"). A wishlisted-only
    # work has no edition rows.
    def owned_editions_of(work)
      work.editions
          .select { |e| e.copies.any? { |c| c.disposition == "owned" } }
          .map { |edition| build_edition(edition) }
    end

    def build_edition(edition)
      isbns = edition.edition_identifiers.each_with_object({}) do |ident, h|
        h[ident.id_type] = ident.value if %w[isbn10 isbn13].include?(ident.id_type)
      end

      Edition.new(
        id: edition.id,
        format: edition.format,
        format_detail: edition.format_detail,
        publisher: edition.publisher.presence,
        year: edition.publish_date&.slice(0, 4),
        isbn10: isbns["isbn10"],
        isbn13: isbns["isbn13"],
        has_cover: edition.cover_image.attached?
      )
    end

    def wishlist_rows
      WishlistItem.where(work_id: nil).includes(:series, cover_image_attachment: :blob).find_each.map do |item|
        WishlistEntry.new(
          id: item.id,
          title: item.title,
          author: item.author_name,
          series: item.series&.name,
          isbn10: item.external_ids["isbn10"],
          isbn13: item.external_ids["isbn13"],
          has_cover: item.cover_image.attached?
        )
      end
    end

    def owned_work_ids
      EditionContent
        .where(edition_id: Copy.where(disposition: "owned").select(:edition_id))
        .distinct.pluck(:work_id).to_set
    end

    def wishlisted_work_ids
      WishlistItem.where.not(work_id: nil).distinct.pluck(:work_id).to_set
    end
  end
end
