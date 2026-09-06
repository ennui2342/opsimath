# One concept in an authority file: the preferred (authorized) form of a
# name, plus its variants. SKOS shape — a Concept with one prefLabel and
# many altLabels. See Authority for the subsystem overview.
class AuthorityTerm < ApplicationRecord
  has_many :authority_variants, dependent: :destroy

  validates :vocabulary, presence: true, inclusion: { in: ->(_) { Authority.vocabularies } }
  validates :preferred_label, presence: true
  validates :preferred_label, uniqueness: { scope: :vocabulary }

  # Every term carries a self-variant (label == preferred_label) so
  # Authority.resolve is a single lookup that also matches the preferred
  # form itself. Kept in sync when the preferred label is renamed.
  after_create :ensure_self_variant
  after_update :resync_self_variant, if: :saved_change_to_preferred_label?

  # Register a variant string. Idempotent — a string already pointing at
  # this term is a no-op; one pointing at a *different* term in this
  # vocabulary raises (never silently re-pointed).
  def register_variant(label)
    normalized = Authority.normalize(label)
    existing = AuthorityVariant.find_by(vocabulary: vocabulary, normalized_label: normalized)
    if existing
      return existing if existing.authority_term_id == id

      raise Conflict, "#{label.inspect} already resolves to #{existing.authority_term.preferred_label.inspect}"
    end

    authority_variants.create!(vocabulary: vocabulary, label: label, normalized_label: normalized)
  end

  # Variant strings other than the preferred form itself.
  def variant_labels
    authority_variants.reject { |v| v.normalized_label == Authority.normalize(preferred_label) }.map(&:label)
  end

  class Conflict < StandardError; end

  private

  def ensure_self_variant
    register_variant(preferred_label)
  end

  def resync_self_variant
    old = Authority.normalize(preferred_label_before_last_save)
    authority_variants.where(normalized_label: old).destroy_all
    ensure_self_variant
  end
end
