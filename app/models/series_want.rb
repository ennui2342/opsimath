# Collecting a whole story series — the record is the want; SeriesWants::Sync
# turns it into wants for each book Mark doesn't have, nightly, so books
# newly added to the series in ISFDB join too. "Not this one" goes in
# excluded_title_ids and sticks.
class SeriesWant < ApplicationRecord
  belongs_to :series
  has_many :wants, dependent: :nullify

  def excluded?(title_id) = excluded_title_ids.include?(title_id.to_i)

  # Stop collecting: the wants this series created go.
  def stop!
    transaction do
      wants.each(&:retire!)
      destroy!
    end
  end
end
