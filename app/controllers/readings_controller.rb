# The reading log, from the book page (docs/CATALOG.md, build step 5).
# Append-only in spirit — a reread is a new Reading — but a past entry can
# be corrected or, with a confirmation, deleted. Finishing can write the
# review at the same time (a draft: publishing to scifipraxis is later).
class ReadingsController < ApplicationController
  before_action :set_work
  before_action :set_reading, only: %i[update destroy]

  def create
    reading = @work.readings.new(reading_params.merge(status: "reading"))
    reading.date_started ||= Date.current
    save_and_return(reading, "Started reading.")
  end

  def update
    @reading.assign_attributes(reading_params)
    @reading.date_finished ||= Date.current if @reading.status_changed? && (@reading.completed? || @reading.dnf?)
    Reading.transaction do
      save_and_return(@reading, -> { notice_for(@reading) }) { attach_review(@reading) }
    end
  end

  def destroy
    @reading.reviews.update_all(reading_id: nil) # a review outlives the reading it came from
    @reading.destroy!
    redirect_to work_path(@work), notice: "Reading deleted."
  end

  private

  def set_work = @work = Work.find(params[:work_id])

  def set_reading = @reading = @work.readings.find(params[:id])

  def reading_params
    params.require(:reading).permit(:status, :edition_id, :source, :date_started, :date_finished, :rating, :dnf_reason, :private_notes)
          .tap { |p| p[:rating] = nil if p.key?(:rating) && p[:rating].blank? }
  end

  # `notice` may be a lambda, called after the save — what happened (Finished,
  # Paused …) is only known from the saved changes.
  def save_and_return(reading, notice)
    if reading.save
      yield if block_given?
      redirect_to work_path(@work), notice: notice.respond_to?(:call) ? notice.call : notice
    else
      redirect_to work_path(@work), alert: reading.errors.full_messages.to_sentence
    end
  end

  def attach_review(reading)
    text = params.dig(:review, :text).to_s.strip
    return if text.blank?

    Review.create!(work: @work, reading:, text:, rating: reading.rating, status: "draft")
  end

  def notice_for(reading)
    return "Finished." if reading.saved_change_to_status? && reading.completed?
    return "Marked did not finish." if reading.saved_change_to_status? && reading.dnf?
    return "Paused." if reading.saved_change_to_status? && reading.paused?
    return "Resumed." if reading.saved_change_to_status? && reading.reading?

    "Reading updated."
  end
end
