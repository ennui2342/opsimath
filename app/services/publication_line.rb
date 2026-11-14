# A publisher's line — ISFDB's publication series (The Women's Press
# Science Fiction; the SF Master Series, 579) — as Mark collects it: every
# number in order, each with whether he has it. From isfdb-adapter's
# /pubseries (cached a day); until the mirror has imported line names, from
# the printings opsimath already knows in that line.
class PublicationLine
  Entry = Struct.new(:pub_id, :title_id, :number, :title, :authors, :publisher, :year, :cover_url, :cover_artist, :work, :status,
                     :pub_ids, keyword_init: true)
  # One per book: ISFDB can file several printings of a book in a line (The
  # Women's Press Woman on the Edge of Time, 1987 and 1989), and having any
  # of them is having the book in the line. `pub_ids` are all of them;
  # `pub_id` is the one shown — his, else one with a cover, else the
  # earliest.
  # status: :yours (an edition of his is one of the line's printings) |
  #         :other_edition (he has the book, another printing) | :wanted (on
  #         the wishlist) | :missing
  STATUS_ORDER = %i[yours other_edition wanted missing].freeze

  attr_reader :id, :name, :entries, :complete

  def self.find(id) = new(id).tap(&:load)

  def initialize(id)
    @id = Integer(id)
  end

  def load
    data = Rails.cache.fetch("isfdb/pubseries/#{@id}", expires_in: 1.day, skip_nil: true) { ::Isfdb::Client.new.publication_series(@id) }
    @complete = data.present?
    rows = data ? data["publications"].map { |p| from_adapter(p) } : known_rows
    @name = data&.dig("name").presence || known.filter_map(&:pub_series_name).first || "ISFDB line #{@id}"
    @entries = by_book(rows.uniq { |e| e.pub_id }.each { |e| e.status = status_of(e) })
    self
  rescue ::Isfdb::ServiceError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.warn("publication line #{@id}: #{e.class}: #{e.message}")
    @complete = false
    @entries = by_book(known_rows.each { |x| x.status = status_of(x) })
    @name = known.filter_map(&:pub_series_name).first || "ISFDB line #{@id}"
    self
  end

  def owned_count = entries.count { |e| e.status == :yours }

  # A printing among an entry's that Mark has (to show his edition).
  def owned_pub_id(entry) = entry.pub_ids.find { |id| owned_pub_ids.include?(id.to_s) }

  # Mark's own edition of a printing in the line (an entry that's :yours).
  def edition_for(entry) = owned_editions[(owned_pub_id(entry) || entry.pub_id).to_s]

  private

  # Printings of one book merged into its first entry's place.
  def by_book(rows)
    rows.group_by { |e| e.work ? "work:#{e.work.id}" : (e.title_id ? "title:#{e.title_id}" : "pub:#{e.pub_id}") }.values.map do |group|
      shown = group.min_by { |e| [ STATUS_ORDER.index(e.status), e.cover_url.present? ? 0 : 1, e.year || 9999 ] }
      shown.dup.tap do |e|
        e.pub_ids = group.map(&:pub_id)
        e.number ||= group.filter_map(&:number).first
        e.status = group.map(&:status).min_by { |s| STATUS_ORDER.index(s) }
      end
    end
  end

  def known = @known ||= ProviderEdition.where(provider: "isfdb", pub_series_id: @id).includes(:work).to_a

  def known_rows
    known.sort_by { |p| [ p.pub_series_num.to_s.to_i.nonzero? || 999_999, p.pub_series_num.to_s, p.publish_date.to_s ] }.map do |p|
      Entry.new(pub_id: p.provider_id.to_i, number: p.pub_series_num, title: p.title.presence || p.work&.title, authors: p.work&.authors&.map(&:name) || [],
                publisher: p.publisher, year: p.year, cover_url: p.cover_url, cover_artist: p.cover_artist, work: p.work)
    end
  end

  def from_adapter(p)
    pub_id = p["_isfdb_pub_id"].to_i
    Entry.new(pub_id:, title_id: p["_isfdb_title_id"], number: p["pub_series_num"].presence, title: p["title"], authors: Array(p["authors"]),
              publisher: p["publisher"],
              year: p["publish_date"].to_s[/\A\d{4}/]&.to_i, cover_url: p["cover_url"].to_s.split("|").first.presence,
              cover_artist: Array(p["cover_artists"]).join(", ").presence,
              work: work_for(pub_id, p["_isfdb_title_id"]))
  end

  # The catalogued book this printing is of: by the printing itself, else
  # by its ISFDB title.
  def work_for(pub_id, title_id)
    known.find { |r| r.provider_id == pub_id.to_s }&.work ||
      (title_id && WorkIdentifier.find_by(id_type: "isfdb_title", value: title_id.to_s)&.work)
  end

  def status_of(entry)
    return :yours if owned_pub_ids.include?(entry.pub_id.to_s)
    return :missing unless entry.work

    statuses = entry.work.statuses
    return :other_edition if statuses.include?(:owned)
    return :wanted if statuses.include?(:wanted)

    :missing
  end

  def owned_pub_ids = owned_editions.keys.to_set

  def owned_editions
    @owned_editions ||= EditionIdentifier.where(id_type: "isfdb", edition_id: Copy.where(disposition: "owned").select(:edition_id))
                                         .includes(edition: [ :copies, :readings, :edition_identifiers, { cover_image_attachment: { blob: :variant_records } },
                                                              { works: [ :provider_editions, { work_contributors: :contributor } ] } ])
                                         .to_h { |i| [ i.value, i.edition ] }
  end
end
