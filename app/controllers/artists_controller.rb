# A cover artist's page (Mark collects for the covers): their covers in his
# catalogue, and their covers on the books he wants — what bargain hunting
# could find. Cover artists are names on editions ("A, B" when shared),
# not records, so the page is keyed by name. Linked from edition cards,
# bargain-hunting covers and finds.
class ArtistsController < ApplicationController
  def show
    @name = params[:name].to_s.strip
    return redirect_to(works_path, alert: "No artist given.") if @name.blank?

    key = @name.downcase
    credited = ->(credit) { credit.to_s.split(", ").any? { |a| a.strip.downcase == key } }

    @editions = Edition.where("cover_artist ILIKE ?", "%#{Edition.sanitize_sql_like(@name)}%")
                       .includes(:copies, :readings, :edition_identifiers, { cover_image_attachment: :blob }, works: { work_contributors: :contributor })
                       .select { |e| credited.call(e.cover_artist) }
                       .sort_by { |e| [ e.publish_date.to_s.presence || "9999", e.works.first&.title.to_s.downcase ] }
    yours = @editions.flat_map { |e| e.edition_identifiers.select { |i| i.id_type == "isfdb" }.map(&:value) }.to_set

    wanted = Want.includes(work: [ :provider_editions, { work_contributors: :contributor } ]).to_a
    @wishlist = wanted.filter_map do |want|
      printings = want.printings.select { |p| credited.call(p.cover_artist) && !yours.include?(p.provider_id) }
      [ want, printings ] if printings.any?
    end.sort_by { |want, _| want.title.to_s.downcase }

    @favourite = CollectingProfile.current.favourite_artists.include?(@name)
  end
end
