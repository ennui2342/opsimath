# A publisher's page: the editions in the catalogue under that imprint.
# Publishers are names on editions, not records, so the page is keyed by
# name — and spellings of one imprint are taken together the way the
# edition picker groups them ("Panther", "Panther Books", "Panther /
# Granada": AddBook::EditionCards.publisher_core). Linked from each
# edition card's publisher.
class PublishersController < ApplicationController
  def show
    @name = params[:name].to_s.strip
    key = AddBook::EditionCards.publisher_core(@name)
    return redirect_to(works_path, alert: "No publisher given.") if key.blank?

    @editions = Edition.where.not(publisher: [ nil, "" ]).includes(:copies, :readings, works: { work_contributors: :contributor })
                       .select { |e| AddBook::EditionCards.publisher_core(e.publisher) == key }
                       .sort_by { |e| [ e.publish_date.to_s.presence || "9999", e.works.first&.title.to_s.downcase ] }
    @spellings = @editions.map(&:publisher).tally.sort_by { |_, n| -n }
  end
end
