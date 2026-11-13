module BookLists
  # Loads a list's entries (docs/LISTS.md): an award category from ISFDB
  # (every year's winner and shortlist, each linked to its title), or a
  # curated list from its data file (config/book_lists/), each entry
  # matched to an ISFDB title by title and author surname. Re-importing
  # replaces the entries; a curated entry keeps the match it had.
  class Import
    CURATED_DIR = Rails.root.join("config/book_lists")

    def initialize(client: Isfdb::Client.new)
      @client = client
    end

    # -> the BookList, or nil if ISFDB has no such category
    def award(category_id)
      data = @client.award_category(category_id) or return
      list = BookList.find_or_initialize_by(key: "isfdb_award_category:#{category_id}")
      award = data.dig("award", "name").to_s
      list.update!(kind: "award", isfdb_award_category_id: category_id.to_i, name: "#{award}: #{data['name']}",
                   short_name: list.short_name.presence || award.sub(/\s+(Award|Memorial Award|Prize)\z/, "").presence || award,
                   source: "ISFDB")
      rows = Array(data["entries"]).filter_map do |e|
        next unless e["status"] # "no award", withdrawn …

        { year: e["year"], status: e["status"], title: CGI.unescapeHTML(e["title"].to_s), author: CGI.unescapeHTML(e["author"].to_s),
          isfdb_title_id: (e["main_title_id"] || e["title_id"]) }
      end
      replace(list, rows)
    end

    # -> the BookList, from config/book_lists/<key>.yml (or `data` in its
    # shape). `rematch` matches every entry afresh, not only unmatched ones.
    def curated(key, data: YAML.load_file(CURATED_DIR.join("#{key}.yml")), rematch: false)
      list = BookList.find_or_initialize_by(key: data.fetch("key"))
      list.update!(kind: "curated", name: data.fetch("name"), short_name: list.short_name.presence || data.fetch("short_name", data["name"]),
                   source: data["source"])
      known = rematch ? {} : list.entries.to_h { |e| [ [ e.title, e.author ], e.isfdb_title_id ] }
      rows = data.fetch("entries").map do |e|
        id = known[[ e["title"], e["author"] ]] || match(e["title"], e["author"], e["year"]) # unmatched: tried again
        { year: e["year"], position: e["position"], status: "listed", title: e["title"], author: e["author"], isfdb_title_id: id }
      end
      replace(list, rows)
    end

    def self.curated_keys = Dir[CURATED_DIR.join("*.yml")].map { |f| File.basename(f, ".yml") }.sort

    private

    def replace(list, rows)
      BookList.transaction do
        list.entries.delete_all
        BookListEntry.insert_all(rows.map { |r| r.merge(book_list_id: list.id, created_at: Time.current, updated_at: Time.current) }) if rows.any?
        list.update!(synced_at: Time.current)
      end
      list.entries.reset
      list
    end

    def fold(text) = I18n.transliterate(CGI.unescapeHTML(text.to_s)).downcase.gsub(/[^a-z0-9]+/, " ").strip.sub(/\A(the|a|an) /, "")

    # The ISFDB main title for a listed book: searched on its title and the
    # first author's surname, then (short or common words crowd that out:
    # "334", "Man Plus") on the title alone; the title must agree once
    # folded — or be ISFDB's with a subtitle ("Blood: A Southern
    # Fantasy") — and an author's surname too. nil when nothing does: a
    # trilogy listed as one entry has no one ISFDB title. ISFDB can hold
    # several titles of one name by one author (The Martian Chronicles of
    # 1950, and a later reissue with other contents): one whose main title
    # is the listed title (a printing titled "Norstrilia" can lead to The
    # Planet Buyer), then the one whose year is nearest the list's.
    def match(title, author, year = nil)
      surname = author.to_s.split(/,| and | & /).first.to_s.split.last.to_s
      by = ->(r) { Array(r["authors"]).any? { |a| fold(a.split.last) == fold(surname) } }
      hits = [ "#{title} #{surname}", title ].lazy.map do |q|
        rows = @client.search(q, limit: 100, editions_per_title: 1).select(&by)
        exact = rows.select { |r| fold(r["title"]) == fold(title) }
        exact.any? ? exact : rows.select { |r| r["title"].to_s.match?(/\A#{Regexp.escape(title)}\s*:/i) }
      end.find(&:any?)
      return unless hits

      mains = hits.filter_map { |r| r["_isfdb_title_id"] }.uniq.filter_map { |id| @client.title(id)&.dig("main") }.uniq { |m| m["id"] }
      best = mains.min_by do |m|
        [ fold(m["title"]) == fold(title) ? 0 : 1, year && m["year"] ? (m["year"].to_i - year.to_i).abs : 9999, m["id"].to_i ]
      end
      best&.dig("id") || hits.first["_isfdb_title_id"]
    rescue Isfdb::ServiceError, Net::OpenTimeout, Net::ReadTimeout => e
      Rails.logger.warn("book list match #{title}: #{e.class}: #{e.message}")
      nil
    end
  end
end
