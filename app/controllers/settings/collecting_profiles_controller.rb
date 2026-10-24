module Settings
  # The collecting profile (docs/BARGAIN_HUNTING.md, "What counts as
  # wanted"): the buy-new window, and favourite artists — computed from
  # the owned collection, adjusted by an always list and a never list.
  class CollectingProfilesController < ApplicationController
    def show
      @profile = CollectingProfile.current
    end

    def update
      @profile = CollectingProfile.current
      shown = Array(params[:shown_artists])
      not_favourite = Array(params[:not_favourite])
      # Never-list entries not on the page this time (now under the
      # threshold) are kept; the ones shown take the checkbox's answer.
      never = (@profile.favourite_artists_never - shown) | not_favourite
      always = params[:favourite_artists_always].to_s.lines.map(&:strip).compact_blank.uniq
      if @profile.update(recent_years: params[:recent_years], favourite_artist_min_owned: params[:favourite_artist_min_owned],
                         favourite_artists_always: always, favourite_artists_never: never)
        redirect_to settings_collecting_profile_path, notice: "Saved."
      else
        flash.now[:alert] = @profile.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity
      end
    end
  end
end
