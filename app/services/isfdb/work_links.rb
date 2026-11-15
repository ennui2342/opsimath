module Isfdb
  # The cascade from an edition's printing to its work (docs/CATALOG.md,
  # "ISFDB links from editions"; Mark, 2026-11-15): he cleans the
  # catalogue by setting each edition to the right ISFDB printing, and
  # everything else follows —
  #
  #   edition's printing → the work's ISFDB title(s) → the work's form,
  #   first-publication year, language, title and series
  #
  # A work's ISFDB titles are *replaced* by the titles its editions are
  # printings of: an anchored edition's printing's own title
  # (provider_work_id); an edition not anchored yet, the title of a printing
  # with its ISBN (one an earlier correction rejected aside — an ISBN can
  # be reused). A link Mark made himself stays (a UK split volume linked to
  # the whole book). When the titles change, the work's details are worked
  # out again from them at once — no queue for later.
  #
  # Nothing changes when there's nothing to go on: a wanted book with no
  # edition, an edition whose printing hasn't been fetched with its title
  # yet, or editions no printing is known for.
  class WorkLinks
    ID_TYPE = "isfdb_title".freeze
    REJECTED = "isfdb_title_rejected".freeze
    Change = Struct.new(:work, :add, :drop, keyword_init: true) # add/drop: [[title id, printing title]]

    def self.sync(work, apply: true, client: Client.new) = new(client:).sync(work, apply:)

    # Every work with an edition: dry run unless `apply`. -> [Change]
    def self.run_all(apply: true, client: Client.new)
      runner = new(client:)
      Work.where(id: EditionContent.select(:work_id))
          .includes(:work_identifiers, :provider_editions, editions: :edition_identifiers)
          .find_each.filter_map { |work| runner.sync(work, apply:) }
    end

    def initialize(client:)
      @client = client
    end

    # -> the Change, or nil when the work's title records are already its
    # editions' (or there's nothing to go on — see #title_records)
    def sync(work, apply: true)
      wanted = title_records(work) or return
      links = work.work_identifiers.select { |i| i.id_type == ID_TYPE }
      keep = links.select { |i| i.source == "manual" }.map(&:value)
      target = (wanted + keep).uniq
      current = links.map(&:value)
      add = target - current
      drop = current - target
      return if add.empty? && drop.empty?

      change = Change.new(work:, add: labelled(work, add), drop: labelled(work, drop))
      apply!(change) if apply
      change
    end

    # The ISFDB title records the work's editions are printings of, or nil
    # when there's nothing (yet) to go on — then a lookup's answer (ISFDB's
    # title search, for a book with no ISBN) stands.
    def title_records(work)
      editions = work.editions.to_a
      return if editions.empty?

      printings = work.provider_editions.select { |p| p.provider == "isfdb" }
      rejected = work.work_identifiers.select { |i| i.id_type == REJECTED }.map(&:value)
      ids = []
      editions.each do |edition|
        if (anchor = edition.edition_identifiers.find { |i| i.id_type == "isfdb" }&.value)
          row = printings.find { |p| p.provider_id == anchor }
          return if row.nil? || row.provider_work_id.blank? # not fetched with its title yet: judged later
          ids << row.provider_work_id
        else
          isbns = edition.edition_identifiers.select { |i| %w[isbn13 isbn10].include?(i.id_type) }
                         .filter_map { |i| i.id_type == "isbn10" ? Isbn.to_13(i.value) : i.value }
          ids.concat(printings.select { |p| p.isbn13.present? && isbns.include?(p.isbn13) }.filter_map(&:provider_work_id) - rejected)
        end
      end
      ids.uniq.presence
    end

    private

    # Each title record with the name its printings give it.
    def labelled(work, ids)
      names = work.provider_editions.select { |p| p.provider == "isfdb" && p.provider_work_id }.to_h { |p| [ p.provider_work_id, p.title ] }
      ids.map { |id| [ id, names[id] || "ISFDB title record #{id}" ] }
    end

    def apply!(change)
      work = change.work
      Work.transaction do
        work.work_identifiers.where(id_type: ID_TYPE, value: change.drop.map(&:first)).delete_all
        change.add.each { |id, _| work.work_identifiers.find_or_create_by!(id_type: ID_TYPE, value: id) { |i| i.source = "editions" } }
        was = change.drop.map(&:last).join(", ")
        CatalogueEvent.record(kind: "relinked", origin: "work_links", work:,
                              details: { added: change.add, dropped: change.drop },
                              summary: "#{work.title}: work now linked to ISFDB title record “#{change.add.map(&:last).join('”, “').presence || '—'}”" \
                                       "#{" (was “#{was}”)" if was.present?}, from its editions' printings")
      end
      cascade(work.reload)
    end

    # The work's details from its new titles, at once: form, year, language
    # (MainTitles), its title by the rule (TitleCleanup), its series and
    # number (WorkSeriesSync, after resetting numbers its printings no
    # longer give).
    def cascade(work)
      one = Work.where(id: work.id)
      MainTitles.run(one, client: @client)
      TitleCleanup.apply(one)
      renumber(work.reload)
      WorkSeriesSync.run(one)
    end

    # WorkSeriesSync only adds, so a number taken from an old title stays
    # otherwise (Live Robots was Ware #2, from Wetware inside it). A series
    # its own printings don't name is left — it may be Mark's.
    def renumber(work)
      own = work.own_isfdb_printings
      work.work_series.includes(:series).each do |ws|
        isfdb = ws.series.isfdb_series_id or next
        named = own.select { |p| p.series_id == isfdb }
        next if named.empty? || ws.position.nil?

        nums = named.map(&:series_num).uniq
        target = nums.one? ? nums.first : nil
        next if ws.position == target

        ws.update!(position: target)
        CatalogueEvent.record(kind: "series", origin: "work_links", work:,
                              summary: "#{work.title}: in #{ws.series.name}#{target ? " ##{format('%g', target)}" : ' without a number'} (from its printings)")
      end
    end
  end
end
