# A non-preferred form that resolves to its AuthorityTerm. `vocabulary`
# is denormalised from the term so "one meaning per string per
# vocabulary" is a real DB unique index on [vocabulary, normalized_label].
class AuthorityVariant < ApplicationRecord
  belongs_to :authority_term

  validates :vocabulary, presence: true
  validates :label, presence: true
  validates :normalized_label, presence: true, uniqueness: { scope: :vocabulary }
end
