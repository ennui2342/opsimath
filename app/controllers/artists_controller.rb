# A cover artist's page (Mark collects for the covers): their covers in his
# catalogue, and their covers on the books he wants — what bargain hunting
# could find. Cover artists are names on editions ("A, B" when shared),
# not records, so the page is keyed by name. Linked from edition cards,
# bargain-hunting covers and finds.
class ArtistsController < ApplicationController
  def show
    @name = params[:name].to_s.strip
    return redirect_to(works_path, alert: "No artist given.") if @name.blank?

    @all_formats = params[:all].present?
    profile = CollectingProfile.current

    key = @name.downcase
    credited = ->(credit) { credit.to_s.split(", ").any? { |a| a.strip.downcase == key } }

    @editions = Edition.where("cover_artist ILIKE ?", "%#{Edition.sanitize_sql_like(@name)}%")
                       .includes(:copies, :readings, :edition_identifiers, { cover_image_attachment: :blob }, works: { work_contributors: :contributor })
                       .select { |e| credited.call(e.cover_artist) }
                       .sort_by { |e| [ e.publish_date.to_s.presence || "9999", e.works.first&.title.to_s.downcase ] }
    yours = @editions.flat_map { |e| e.edition_identifiers.select { |i| i.id_type == "isfdb" }.map(&:value) }.to_set

    # The same covers bargain hunting offers each book
    # (CollectingProfile#offered_printings) — the rule's, or all formats.
    wanted = Want.includes(work: [ :provider_editions, { work_contributors: :contributor } ]).to_a
    @wishlist = wanted.filter_map do |want|
      printings = profile.offered_printings(want, all_formats: @all_formats)
                         .select { |p| credited.call(p.cover_artist) && !yours.include?(p.provider_id) }
      [ want, printings ] if printings.any?
    end.sort_by { |want, _| want.title.to_s.downcase }

    # Their covers on books Mark has but isn't hunting: the printings
    # bargain hunting would offer for that book (the same rule, or all
    # formats) carrying this artist's cover — one per distinct scan — each
    # with a "want just this cover".
    wanted_work_ids = wanted.map(&:work_id).to_set
    work_ids = ProviderEdition.where(provider: "isfdb").where("cover_artist ILIKE ?", "%#{ProviderEdition.sanitize_sql_like(@name)}%")
                              .where.not(work_id: wanted_work_ids.to_a).distinct.pluck(:work_id)
    @elsewhere = Work.where(id: work_ids).includes(:provider_editions, work_contributors: :contributor).flat_map do |work|
      profile.offered_printings(Want.new(work:), all_formats: @all_formats)
             .select { |p| credited.call(p.cover_artist) && !yours.include?(p.provider_id) }
             .group_by { |p| p.cover_url.presence || "pub:#{p.provider_id}" }.values
    end.sort_by { |ps| [ ps.first.work.title.to_s.downcase, ps.filter_map(&:year).min || 9999 ] }

    @favourite = CollectingProfile.current.favourite_artists.include?(@name)
  end

  # The star: this artist a favourite, or not (CollectingProfile#favourite!).
  def favourite
    name = params[:name].to_s.strip
    CollectingProfile.current.favourite!(name, on: params[:on] == "1")
    redirect_to artist_path(name:, all: params[:all].presence)
  end

  # "Want this cover": the book onto the wishlist hunting just these
  # printings (one cover) — an upgrade hunt for a book Mark has.
  def want_cover
    work = Work.find(params[:work_id])
    ids = work.provider_editions.where(provider: "isfdb", provider_id: Array(params[:pub_ids]).map(&:to_s)).pluck(:provider_id).map(&:to_i)
    return redirect_back_or_to(artist_path(name: params[:name]), alert: "Those printings aren't known for that book.") if ids.empty?

    want = work.want || work.create_want!
    want.update!(printing_override_ids: (Array(want.printing_override_ids) | ids))
    CatalogueEvent.record(kind: "wanted", work:, summary: "Wanted the #{params[:name]} cover of #{work.title}")
    redirect_to artist_path(name: params[:name], all: params[:all].presence), notice: "Now hunting the #{params[:name]} cover of “#{work.title}”."
  end
end
