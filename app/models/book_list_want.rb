# Collecting a list (docs/LISTS.md): BookListWants::Sync turns every book
# on it in scope — the winners, or the whole shortlist; from a year, if
# set — that Mark doesn't have into a want, nightly, so a new year's
# entries join too. "Not this one" goes in excluded_title_ids and sticks.
class BookListWant < ApplicationRecord
  SCOPES = %w[winners shortlist].freeze

  belongs_to :book_list
  has_many :wants, dependent: :nullify

  validates :scope, inclusion: { in: SCOPES }

  def excluded?(title_id) = excluded_title_ids.include?(title_id.to_i)

  def covers?(entry) = entry.in_scope?(scope) && (from_year.nil? || entry.year.nil? || entry.year >= from_year)

  # Stop collecting: the wants this list created go.
  def stop!
    transaction do
      wants.each(&:retire!)
      destroy!
    end
  end
end
