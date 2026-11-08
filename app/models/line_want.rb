# Collecting a whole publisher's line — The Women's Press Science
# Fiction, the SF Master Series (ISFDB publication series). The record is
# the want; LineWants::Sync turns it into wants for each number Mark
# doesn't have, nightly, so numbers newly catalogued in ISFDB join too.
# "Not this one" goes in excluded_pub_ids and sticks.
class LineWant < ApplicationRecord
  has_many :wants, dependent: :nullify

  validates :pub_series_id, presence: true, uniqueness: true

  def excluded?(pub_id) = excluded_pub_ids.include?(pub_id.to_i)

  # Stop collecting: the wants this line created go (a book Mark wanted
  # anyway keeps its want).
  def stop!
    transaction do
      wants.each(&:retire!)
      destroy!
    end
  end
end
