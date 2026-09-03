module Mobile
  # The denormalised "shop view" of the collection: one flat list of
  # entries, each a book you own or have wishlisted, carrying everything
  # the offline lookup PWA needs to answer "owned / wishlisted / neither"
  # for a book in hand (docs/MOBILE.md constraint 3).
  #
  # A single searchable unit deliberately: a catalogued work and an
  # unmatched wishlist item both become an `Entry`, so the client runs one
  # search / one barcode lookup, not one per collection. A work's
  # one-to-many editions hang off its entry (`editions`) and are joined
  # only after a hit, never searched.
  #
  # Format-agnostic plain data — Mobile::SnapshotBuilder turns it into
  # snapshot.sqlite3; the same shape is the natural basis for a public API.
  # "Do I own an edition of this work" and "is this work wishlisted" each
  # resolve in one query, not a per-work check.
  class ShopView
    Entry = Struct.new(
      :id,               # "work:<id>" / "wishlist:<id>" — unique within a snapshot
      :kind,             # "work" | "wishlist"
      :title, :subtitle, :authors, :series, :series_position, :original_year,
      :owned, :wishlisted,
      :isbn10, :isbn13, :has_cover, # entry-level — set only for kind "wishlist"
      :editions,                    # [Edition] — set only for kind "work"
      keyword_init: true
    )
    Edition = Struct.new(
      :id, :format, :format_detail, :publisher, :year, :page_count, :disposition,
      :isbn10, :isbn13, :isfdb, :goodreads, :has_cover,
      keyword_init: true
    )
    Result = Struct.new(:entries, keyword_init: true)

    def self.build = new.build

    def build
      Result.new(entries: (work_entries + wishlist_entries).sort_by { |e| e.title.to_s.downcase })
    end

    private

    def work_entries
      owned = owned_work_ids
      wishlisted = wishlisted_work_ids

      work_scope.where(id: owned | wishlisted).find_each.map do |work|
        build_work_entry(work, owned:, wishlisted:)
      end
    end

    def work_scope
      ::Work.includes(
        { work_contributors: :contributor },
        { work_series: :series },
        { editions: [ :edition_identifiers, :copies, { cover_image_attachment: :blob } ] }
      )
    end

    def build_work_entry(work, owned:, wishlisted:)
      first_series = work.work_series.min_by { |ws| ws.position || Float::INFINITY }

      Entry.new(
        id: "work:#{work.id}",
        kind: "work",
        title: work.title,
        subtitle: work.subtitle.presence,
        authors: authors_of(work),
        series: first_series&.series&.name,
        series_position: first_series&.position && format("%g", first_series.position),
        original_year: work.original_publication_year,
        owned: owned.include?(work.id),
        wishlisted: wishlisted.include?(work.id),
        editions: editions_of(work)
      )
    end

    def authors_of(work)
      work.work_contributors
          .select { |wc| wc.role == "author" }
          .sort_by { |wc| wc.display_order || Float::INFINITY }
          .map { |wc| wc.contributor.name }
    end

    # Every edition of this work that a copy has passed through — owned
    # ones plus the retired ones (`replaced`/`sold`/…), so the shop card
    # can show which printing you hold now and which you used to.
    # `disposition` per edition carries that; only `owned` editions feed
    # the exact-match `isbn_index` (see SnapshotBuilder#isbn_rows).
    # Owned first, then by id. A wishlisted-only work has no edition rows.
    def editions_of(work)
      work.editions
          .select { |e| e.copies.any? }
          .sort_by { |e| [ owned?(e) ? 0 : 1, e.id ] }
          .map { |edition| build_edition(edition) }
    end

    def owned?(edition) = edition.copies.any? { |c| c.disposition == "owned" }

    # An edition with a mix of copies reads as owned if any copy is; else
    # it takes the disposition of its (single, realistically) retired copy.
    def disposition_of(edition)
      return "owned" if owned?(edition)

      edition.copies.first&.disposition
    end

    def build_edition(edition)
      ids = edition.edition_identifiers.each_with_object({}) { |i, h| h[i.id_type] = i.value }

      Edition.new(
        id: edition.id,
        format: edition.format,
        format_detail: edition.format_detail,
        publisher: edition.publisher.presence,
        year: edition.publish_date&.slice(0, 4),
        page_count: edition.page_count,
        disposition: disposition_of(edition),
        isbn10: ids["isbn10"],
        isbn13: ids["isbn13"],
        isfdb: ids["isfdb"],
        goodreads: ids["goodreads"],
        has_cover: edition.cover_image.attached?
      )
    end

    def wishlist_entries
      WishlistItem.where(work_id: nil).includes(:series, cover_image_attachment: :blob).find_each.map do |item|
        Entry.new(
          id: "wishlist:#{item.id}",
          kind: "wishlist",
          title: item.title,
          authors: Array(item.author_name.presence),
          series: item.series&.name,
          original_year: nil,
          owned: false,
          wishlisted: true,
          isbn10: item.external_ids["isbn10"],
          isbn13: item.external_ids["isbn13"],
          has_cover: item.cover_image.attached?,
          editions: []
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
