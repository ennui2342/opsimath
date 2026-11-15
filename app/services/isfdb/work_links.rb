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
      unnumber_omnibus(work) if apply
      wanted = title_records(work) or return
      links = work.work_identifiers.select { |i| i.id_type == ID_TYPE }
      current = links.map(&:value)
      keep = links.select { |i| i.source == "manual" }.map(&:value)
      return if (wanted - current).empty? && (current - wanted - keep).empty? # already so: no ISFDB calls

      # Compared by main title record: an edition's publication often
      # belongs to a variant title record (a reissue, a retitling) of the
      # one the work is linked to — the same book, nothing to change.
      mains = wanted.map { |id| main_id(id) }
      return if mains.any?(&:nil?) # ISFDB unreadable: changed on a later run
      add = wanted.reject { |id| current.any? { |c| main_id(c) == main_id(id) } }.uniq { |id| main_id(id) }
      drop = (current - keep).reject { |c| mains.include?(main_id(c)) || main_id(c).nil? }
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
          id = printings.find { |p| p.provider_id == anchor }&.provider_work_id.presence || chosen_title(edition, anchor)
          return if id.blank? # not fetched with its title yet: judged later
          ids << id
        else
          isbns = edition.edition_identifiers.select { |i| %w[isbn13 isbn10].include?(i.id_type) }
                         .filter_map { |i| i.id_type == "isbn10" ? Isbn.to_13(i.value) : i.value }
          ids.concat(printings.select { |p| p.isbn13.present? && isbns.include?(p.isbn13) }.filter_map(&:provider_work_id) - rejected)
        end
      end
      ids.uniq.presence
    end

    # An omnibus isn't one volume: no number in a series its own ISFDB
    # printings don't number (1Q84 #3, from Goodreads) — whether or not the
    # work was relinked.
    def unnumber_omnibus(work)
      return unless work.literary_form == "omnibus"

      own = work.own_isfdb_printings
      work.work_series.includes(:series).each do |ws|
        next if ws.position.nil? || own.any? { |p| p.series_id && p.series_id == ws.series.isfdb_series_id && p.series_num }

        ws.update!(position: nil)
        CatalogueEvent.record(kind: "series", origin: "work_links", work:, summary: "#{work.title}: in #{ws.series.name} without a number (an omnibus)")
      end
    end

    private

    # The title record of the printing an edition was set to, as recorded
    # when it was chosen (its ISFDB source record) — for a printing that
    # isn't among the work's stored ones (chosen from a search: New Worlds
    # 4's Sphere printing of Moorcock's New Worlds Quarterly 4, 2026-11-15).
    def chosen_title(edition, anchor)
      EnrichmentRecord.where(entity: edition, provider: "isfdb", external_id: anchor).order(:fetched_at).last
                      &.raw_payload&.then { |raw| (raw["work_id"] || raw["_isfdb_title_id"]).presence&.to_s }
    end

    def main_id(id)
      @mains ||= {}
      @mains.fetch(id.to_s) { @mains[id.to_s] = @client.title(id)&.dig("main", "id")&.to_s }
    rescue Isfdb::ServiceError, Net::OpenTimeout, Net::ReadTimeout
      nil
    end

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
    # (MainTitles), its title by the rule (TitleCleanup), its authors
    # (AuthorCleanup — New Worlds 4 kept Garnett's name after relinking to
    # Moorcock's, 2026-11-15), its series and
    # number (WorkSeriesSync, after resetting numbers its printings no
    # longer give).
    def cascade(work)
      one = Work.where(id: work.id)
      MainTitles.run(one, client: @client)
      TitleCleanup.apply(one)
      AuthorCleanup.sync_work(work, client: @client)
      renumber(work.reload)
      WorkSeriesSync.run(one)
    end

    # The work's series after a relink — WorkSeriesSync only adds, so what
    # the old title record gave stays otherwise:
    # - in an ISFDB series its own printings name: their number (Live
    #   Robots was Ware #2, from Wetware inside it);
    # - in an ISFDB series they don't name: out — it came from the old
    #   record (New Worlds 4 in Garnett's New Worlds, Mark, 2026-11-15);
    # - an omnibus in any other series: no number — it isn't one volume
    #   (1Q84 #3, from Goodreads).
    # Unjudged when the work has no own printings to go on.
    def renumber(work)
      own = work.own_isfdb_printings
      return if own.empty?

      work.work_series.includes(:series).each do |ws|
        isfdb = ws.series.isfdb_series_id
        named = isfdb ? own.select { |p| p.series_id == isfdb } : []
        if isfdb && named.empty?
          CatalogueEvent.record(kind: "series", origin: "work_links", work:,
                                summary: "#{work.title}: out of #{ws.series.name} (it came from the work's old ISFDB title record)")
          ws.destroy!
          next
        end

        nums = named.map(&:series_num).uniq
        target = if isfdb then nums.one? ? nums.first : nil
        elsif work.literary_form == "omnibus" then nil
        else ws.position
        end
        next if ws.position == target

        ws.update!(position: target)
        CatalogueEvent.record(kind: "series", origin: "work_links", work:,
                              summary: "#{work.title}: in #{ws.series.name}#{target ? " ##{format('%g', target)}" : ' without a number'}" \
                                       "#{' (an omnibus)' if !isfdb && work.literary_form == 'omnibus'}")
      end
    end
  end
end
