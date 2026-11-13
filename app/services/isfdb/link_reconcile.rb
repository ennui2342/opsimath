module Isfdb
  # A book's ISFDB titles checked against its editions (docs/CATALOG.md,
  # "ISFDB links from editions"). An edition anchored to an ISFDB printing
  # is a printing of that printing's own title (provider_work_id); the
  # book's links should be those titles — compared by main title, so a
  # variant (Village of the Damned for The Midwich Cuckoos) is the same
  # book. Until isfdb-adapter's 2026-11-14 fix an omnibus printing was
  # credited to a novel in it, and links learnt from ISBNs took that on
  # (Peace and War linked to The Forever War, then retitled after it).
  #
  # For each book with anchored editions whose printings have their title:
  #   - a link no edition supports is dropped, and remembered as rejected
  #     (KnownEditionsRefresh won't put it back);
  #   - an edition's title the book isn't linked to is added — unless it
  #     was rejected before: a conflict for Mark, and the book is left as
  #     it is;
  #   - a title taken from a dropped link ("The Forever War") goes back to
  #     the book's own title before ISFDB's, for the right record to set
  #     again (Isfdb::MainTitles, TitleCleanup).
  # `plan` is a dry run.
  class LinkReconcile
    REJECTED = "isfdb_title_rejected".freeze
    Change = Struct.new(:work, :drop, :add, :conflicts, :restore_title, keyword_init: true) # drop/add/conflicts: [[id, main title]]

    attr_reader :skipped

    def self.plan(...) = new(...).plan

    def self.apply(...) = new(...).apply

    def initialize(works: nil, client: Client.new)
      @works = works
      @client = client
      @mains = {}
      @skipped = 0
    end

    def plan
      @plan ||= scope.find_each.filter_map { |work| change_for(work) }
    end

    # -> books changed
    def apply
      changed = plan.select { |c| c.drop.any? || c.add.any? }
      changed.each do |c|
        Work.transaction do
          c.drop.each do |id, _|
            c.work.work_identifiers.where(id_type: "isfdb_title", value: id).delete_all
            c.work.work_identifiers.find_or_create_by!(id_type: REJECTED, value: id) { |i| i.source = "editions" }
          end
          c.add.each { |id, _| c.work.work_identifiers.find_or_create_by!(id_type: "isfdb_title", value: id) { |i| i.source = "editions" } }
          TitleCleanup.retitle(c.work, c.restore_title, source: "editions") if c.restore_title
          CatalogueEvent.record(kind: "relinked", origin: "link_reconcile", work: c.work,
                                summary: "#{c.work.title}: ISFDB link corrected from its editions" \
                                         "#{" (was #{c.drop.map(&:last).join(', ')})" if c.drop.any?}")
        end
      end
      works = Work.where(id: changed.map { |c| c.work.id })
      MainTitles.run(works, client: @client) if changed.any?
      TitleCleanup.apply(works) if changed.any?
      changed.size
    end

    private

    def scope
      works = @works || Work.where(id: EditionContent.joins(edition: :edition_identifiers)
                                                     .where(edition_identifiers: { id_type: "isfdb" }).select(:work_id))
      works.includes(:work_identifiers, :work_alternate_titles, :provider_editions, editions: :edition_identifiers)
    end

    def change_for(work)
      anchors = work.editions.flat_map(&:edition_identifiers).select { |i| i.id_type == "isfdb" }.map(&:value).to_set
      printings = work.provider_editions.select { |p| p.provider == "isfdb" && anchors.include?(p.provider_id) }
      # Not judged until every anchored printing has its title (the
      # 2026-11-14 refetch), or when ISFDB's record can't be read.
      return (@skipped += 1) && nil if printings.empty? || printings.size < anchors.size || printings.any? { |p| p.provider_work_id.blank? }

      own = printings.map(&:provider_work_id).uniq
      links = work.work_identifiers.select { |i| i.id_type == "isfdb_title" }.map(&:value)
      rejected = work.work_identifiers.select { |i| i.id_type == REJECTED }.map(&:value)
      own_mains = own.filter_map { |id| main(id)&.dig("id")&.to_s }.to_set
      return (@skipped += 1) && nil if own_mains.size < own.size

      link_mains = links.to_h { |id| [ id, main(id)&.dig("id")&.to_s ] }
      return (@skipped += 1) && nil if link_mains.values.any?(&:nil?) # unreadable: never dropped on that
      drop = links.reject { |id| own_mains.include?(link_mains[id]) }
      wanted = own.reject { |id| link_mains.values.include?(main(id)["id"].to_s) }.uniq { |id| main(id)["id"] }
      conflicts, add = wanted.partition { |id| rejected.include?(id) || rejected.include?(main(id)["id"].to_s) }
      # An anchor to a printing whose title was rejected is the doubtful
      # one (The Midwich Cuckoos' ISBN was a schools chapbook's): nothing
      # changes on it, Mark decides.
      drop, add = [], [] if conflicts.any?
      return if drop.empty? && add.empty? && conflicts.empty?

      Change.new(work:, drop: labelled(drop), add: labelled(add), conflicts: labelled(conflicts),
                 restore_title: restore_title(work, drop))
    end

    # The book's title before ISFDB's, when its current title came from a
    # link being dropped.
    def restore_title(work, drop)
      return if drop.empty? || work.field_sources["title"] == "manual"
      return unless drop.any? { |id| fold(main(id)&.dig("title")) == fold(work.title) }

      work.work_alternate_titles.select { |a| a.note.to_s.include?("ISFDB") }.min_by(&:created_at)&.title
    end

    def labelled(ids) = ids.map { |id| [ id, CGI.unescapeHTML(main(id)&.dig("title").to_s) ] }

    def main(id) = @mains.fetch(id.to_s) { @mains[id.to_s] = @client.title(id)&.dig("main") }

    def fold(text) = I18n.transliterate(CGI.unescapeHTML(text.to_s)).downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
