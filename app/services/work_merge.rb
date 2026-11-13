# Two records of one book made one (2026-11-13: the same ISFDB title in
# the catalogue twice — an import that didn't see the first, or collecting
# a line that listed a book twice). Everything on `drop` moves to `keep` —
# editions, readings, reviews, the want, series, credits, subjects, tags,
# identifiers, alternate titles, history — without doubling what `keep`
# already has; `keep`'s blank fields take `drop`'s; then `drop` goes.
# ISFDB printings are refetched for `keep` by the nightly refresh (its
# ISBNs have changed).
class WorkMerge
  # Rows that simply move.
  MOVE = [ Reading, Review, CatalogueEvent ].freeze
  # Rows that move unless `keep` has one with the same key.
  JOIN = { EditionContent => %w[edition_id], WorkContributor => %w[contributor_id role], WorkSeries => %w[series_id],
           WorkGenre => %w[genre_id], WorkSubject => %w[subject_id], WorkTag => %w[tag_id], WorkAward => %w[award_id],
           WorkIdentifier => %w[id_type value], WorkAlternateTitle => %w[title], RecommendationDismissal => [],
           RecommendationShow => %w[shown_on], EbayListing => %w[ebay_item_id] }.freeze
  FIELDS = %w[subtitle original_publication_year original_language description isfdb_main_title].freeze

  def self.merge!(keep:, drop:, force: false) = new(keep:, drop:, force:).merge!

  # The ISFDB titles a book's anchored editions are printings of.
  def self.edition_titles(work)
    pubs = EditionIdentifier.where(id_type: "isfdb", edition_id: work.editions.select(:id)).pluck(:value)
    ProviderEdition.where(work:, provider: "isfdb", provider_id: pubs).where.not(provider_work_id: nil).pluck(:provider_work_id).to_set
  end

  class Different < StandardError; end

  # Refused when both books' editions are printings of different ISFDB
  # titles (their own titles, provider_work_id): two books, not one —
  # Peace and War, the omnibus, was merged into The Forever War on a shared
  # (wrong) link, 2026-11-13. `force:` for a variant ISFDB keeps apart.
  def initialize(keep:, drop:, force: false)
    raise ArgumentError, "a book can't be merged into itself" if keep.id == drop.id

    mine, theirs = [ keep, drop ].map { |w| self.class.edition_titles(w) }
    if !force && mine.any? && theirs.any? && !mine.intersect?(theirs)
      raise Different, "their editions are printings of different ISFDB titles (#{mine.to_a.join(', ')} / #{theirs.to_a.join(', ')})"
    end

    @keep = keep
    @drop = drop
  end

  def merge!
    Work.transaction do
      MOVE.each { |model| model.where(work_id: @drop.id).update_all(work_id: @keep.id) }
      JOIN.each { |model, key| join(model, key) }
      Work.connection.exec_update("UPDATE wishlist_items SET work_id = $1 WHERE work_id = $2", "WorkMerge", [ @keep.id, @drop.id ]) # legacy table
      want
      EnrichmentRecord.where(entity: @drop).update_all(entity_id: @keep.id)
      @drop.provider_editions.delete_all
      @drop.provider_edition_refreshes.delete_all
      FIELDS.each { |f| @keep[f] = @drop[f] if @keep[f].blank? && @drop[f].present? }
      @keep.save!
      CatalogueEvent.record(kind: "merged", work: @keep, summary: "#{@keep.title}: merged with a second record of the same book (##{@drop.id})")
      @drop.reload.destroy!
    end
    @keep
  end

  private

  def join(model, key)
    have = model.where(work_id: @keep.id).pluck(*key, :id).map { |r| Array(r)[0...key.size] }
    model.where(work_id: @drop.id).find_each do |row|
      have.include?(key.map { |c| row[c] }) ? row.delete : row.update_columns(work_id: @keep.id)
    end
  end

  # One want: `keep`'s, hunting both wants' printings (a want hunting by
  # the collecting rule — no override — keeps the rule's printings), its
  # other settings filled from `drop`'s.
  def want
    theirs = @drop.want or return
    mine = @keep.reload.want
    return theirs.update_columns(work_id: @keep.id) if mine.nil?

    unless mine.printing_override_ids.nil? && theirs.printing_override_ids.nil?
      rule = -> { CollectingProfile.current.verdict(mine).wanted.map(&:isfdb_pub_id) }
      mine.printing_override_ids = (mine.printing_override_ids || rule.call) | (theirs.printing_override_ids || rule.call)
    end
    mine.seed_isbns |= theirs.seed_isbns
    %w[priority notes target_price buy_new_override cover_url line_want_id series_want_id].each { |f| mine[f] = theirs[f] if mine[f].nil? }
    mine.external_ids = theirs.external_ids.merge(mine.external_ids)
    theirs.destroy!
    mine.save!
  end
end
