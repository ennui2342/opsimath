# The home page (docs/HOME.md): what Mark's reading, the year against its
# goal and his pace, what to read next, series to finish, and his own
# recent activity.
class HomeController < ApplicationController
  def show
    @stats = ReadingStats.new
    @goal = @stats.goal
    @reading = Reading.where(status: %w[reading paused]).includes(work: [ :provider_editions, { work_contributors: :contributor } ],
                                                                  edition: [ :copies, :readings, :edition_identifiers, { cover_image_attachment: { blob: :variant_records } } ])
                      .order(date_started: :desc).to_a
    recommender = Recommendations.new(stats: @stats)
    @picks = recommender.picks(3)
    @quick_win = recommender.quick_win?
    @picks.each { |p| RecommendationShow.find_or_create_by!(work: p.work, shown_on: Date.current) { |s| s.reason = p.reason.to_s } }
    @series = SeriesToFinish.top(5)
    @river = CatalogueEvent.from_web.includes(:work).order(created_at: :desc).limit(40).group_by { |e| e.created_at.to_date }
  end

  # "Not now" (a month) / "Not for me" (for good) on a recommendation.
  def dismiss
    dismissal = RecommendationDismissal.find_or_initialize_by(work_id: params[:work_id])
    dismissal.update!(until: params[:for_good].present? ? nil : 30.days.from_now)
    redirect_to root_path
  end

  def goal
    goal = ReadingGoal.find_or_initialize_by(year: Date.current.year)
    goal.update(target: params[:target].to_i) ? redirect_to(root_path) : redirect_to(root_path, alert: "A goal is a number of books.")
  end
end
