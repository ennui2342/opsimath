module Settings
  # Add or remove a single variant on an existing term, from the settings
  # screen. Both re-run the handler (apply on add, retract on remove) so
  # the catalog and the conflict queue stay in step.
  class AuthorityVariantsController < ApplicationController
    before_action :set_vocabulary

    def create
      term = term_scope.find(params[:authority_term_id])
      term.register_variant(params[:label].to_s.strip)
      result = @handler.apply(term)
      redirect_to settings_authority_path(@vocabulary),
                  notice: "Added variant — #{result.editions_rewritten} rewritten, #{result.conflicts_cleared} conflict(s) cleared."
    rescue AuthorityTerm::Conflict, ActiveRecord::RecordInvalid => e
      redirect_to settings_authority_path(@vocabulary), alert: e.message
    end

    def destroy
      variant = AuthorityVariant.where(vocabulary: @vocabulary).find(params[:id])
      preferred = variant.authority_term.preferred_label
      label = variant.label
      variant.destroy!
      result = @handler.retract(removed_labels: [ label ], preferred_label: preferred)
      redirect_to settings_authority_path(@vocabulary),
                  notice: "Removed variant “#{label}” — re-checked #{result.editions_reprocessed} edition(s), #{result.conflicts_raised} conflict(s) re-raised."
    end

    private

    def set_vocabulary
      @vocabulary = params[:vocabulary]
      head(:not_found) && return unless Authority.vocabulary?(@vocabulary)

      @handler = Authority.handler(@vocabulary)
    end

    def term_scope = AuthorityTerm.where(vocabulary: @vocabulary)
  end
end
