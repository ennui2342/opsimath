module Settings
  # The authority-control settings screens. #show is one vocabulary's
  # authority file — its terms, their variants, and how much of the
  # catalog each touches. All vocabulary-specific work (rewrite, the
  # re-enrich sweep) is delegated to the registered handler, so this
  # controller stays generic across present and future vocabularies.
  class AuthoritiesController < ApplicationController
    before_action :set_vocabulary, only: %i[show rescan]

    def index
      @vocabularies = Authority.vocabularies.map do |v|
        { key: v, handler: Authority.handler(v), term_count: AuthorityTerm.where(vocabulary: v).count }
      end
    end

    def show
      @terms = AuthorityTerm.where(vocabulary: @vocabulary)
                            .includes(:authority_variants)
                            .sort_by { |t| t.preferred_label.downcase }
      @usage = @terms.to_h { |t| [ t.id, @handler.usage(t) ] }
    end

    # Re-run the handler's sweep over every term — for when variants were
    # added directly here, or new conflicts arrived since.
    def rescan
      cleared = @terms_scope.sum { |t| @handler.apply(t).conflicts_cleared }
      redirect_to settings_authority_path(@vocabulary), notice: "Re-scanned — #{cleared} conflict(s) cleared."
    end

    private

    def set_vocabulary
      @vocabulary = params[:vocabulary]
      return head(:not_found) unless Authority.vocabulary?(@vocabulary)

      @handler = Authority.handler(@vocabulary)
      @terms_scope = AuthorityTerm.where(vocabulary: @vocabulary)
    end
  end
end
