module Settings
  # Establish / rename / retract a term in one authority file. #create is
  # reached from both the settings screen (HTML) and the inline "same
  # publisher?" panel on the enrichment_conflict review screen
  # (Turbo Stream, `from_decision_id`) — after the term is applied it
  # re-renders that decision, which by then has publisher gone from its
  # bundle (or advances if the decision fully resolved).
  class AuthorityTermsController < ApplicationController
    before_action :set_vocabulary

    # Dry run — what `create` would rewrite, each edition tagged by
    # whether ISFDB corroborates it. JSON for the inline panel's compact
    # summary; HTML for the settings confirm page.
    def preview
      @preferred = preferred_label
      @variant_labels = variant_labels
      @preview = @handler.preview(preferred: @preferred, variant_labels: @variant_labels)
      respond_to do |format|
        format.json do
          render json: {
            rewritten: @preview.rewritten, corroborated: @preview.corroborated,
            contradicted: @preview.contradicted, unmatched: @preview.unmatched, risky: @preview.risky?
          }
        end
        format.html { render :preview }
      end
    end

    def create
      # settings goes through the confirm page first; the inline panel has
      # already shown its own preview, so it passes confirm
      return redirect_to(preview_path) unless params[:confirm].present? || params[:from_decision_id].present?

      @term = AuthorityTerm.find_or_create_by!(vocabulary: @vocabulary, preferred_label: preferred_label)
      variant_labels.each { |label| @term.register_variant(label) }
      @result = @handler.apply(@term)
      respond(notice: "Established “#{@term.preferred_label}” — #{summary(@result)}.")
    rescue AuthorityTerm::Conflict, ActiveRecord::RecordInvalid => e
      respond(alert: e.message, status: :unprocessable_entity)
    end

    def update
      @term = term_scope.find(params[:id])
      @term.update!(preferred_label: preferred_label) if preferred_label.present?
      @result = @handler.apply(@term)
      redirect_to settings_authority_path(@vocabulary), notice: "Renamed — #{summary(@result)}."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to settings_authority_path(@vocabulary), alert: e.message
    end

    def destroy
      term = term_scope.find(params[:id])
      removed = term.authority_variants.map(&:label)
      preferred = term.preferred_label
      term.destroy!
      result = @handler.retract(removed_labels: removed, preferred_label: preferred)
      redirect_to settings_authority_path(@vocabulary),
                  notice: "Retracted “#{preferred}” — #{result.editions_restored} value(s) restored, #{result.conflicts_raised} conflict(s) re-raised."
    end

    private

    def set_vocabulary
      @vocabulary = params[:vocabulary]
      head(:not_found) && return unless Authority.vocabulary?(@vocabulary)

      @handler = Authority.handler(@vocabulary)
    end

    def term_scope = AuthorityTerm.where(vocabulary: @vocabulary)

    def preview_path
      settings_authority_terms_preview_path(@vocabulary, preferred_label: preferred_label, variant_labels: variant_labels)
    end

    # The inline panel offers current / proposed / "other" (free text).
    def preferred_label
      raw = params[:preferred_label].to_s.strip
      raw == "__other__" ? params[:preferred_label_other].to_s.strip : raw
    end

    # Accepts a newline- or comma-separated string, or an array. Drops
    # blanks and the preferred form itself (which is always a self-variant).
    def variant_labels
      raw = params[:variant_labels]
      list = raw.is_a?(Array) ? raw.flatten : raw.to_s.split(/[\r\n,]+/)
      list.map(&:strip).reject(&:blank?).uniq
          .reject { |l| Authority.normalize(l) == Authority.normalize(preferred_label) }
    end

    def summary(result)
      [
        ("#{result.editions_rewritten} edition#{'s' unless result.editions_rewritten == 1} rewritten" if result.editions_rewritten.positive?),
        ("#{result.conflicts_cleared} conflict#{'s' unless result.conflicts_cleared == 1} cleared" if result.conflicts_cleared.positive?)
      ].compact.join(", ").presence || "no records affected"
    end

    def respond(notice: nil, alert: nil, status: :ok)
      @message = notice || alert
      @level = alert ? :alert : :notice
      @from_decision = PendingDecision.find_by(id: params[:from_decision_id])
      @kind = params[:kind].presence
      # after establishing, the from-decision has usually lost "publisher"
      # from its bundle; keep showing it if it still has work, else move on
      @from_decision = nil unless @from_decision&.pending?
      @next_decision = @from_decision || PendingDecision.next_pending(kind: @kind)

      respond_to do |format|
        format.turbo_stream { render "established", status: status }
        format.html do
          redirect_target = @from_decision ? pending_decision_path(@from_decision, kind: @kind) : settings_authority_path(@vocabulary)
          redirect_to redirect_target, notice: notice, alert: alert
        end
      end
    end
  end
end
