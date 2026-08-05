class Work < ApplicationRecord
  has_paper_trail

  enum :literary_form, {
    novel: "novel",
    novella: "novella",
    short_story: "short_story",
    collection: "collection",
    anthology: "anthology",
    nonfiction: "nonfiction",
    essay: "essay",
    # A standalone magazine/periodical issue — a genuinely different
    # structural type from anthology (MARC/ONIX both distinguish serial/
    # continuing resources from monographs), not a novel or an edited
    # one-off collection. See docs/INTEGRATIONS.md's Phase 2 addendum.
    periodical: "periodical"
  }

  has_many :work_alternate_titles, dependent: :destroy
  has_many :work_contributors, dependent: :destroy
  has_many :contributors, through: :work_contributors
  has_many :work_series, dependent: :destroy
  has_many :series, through: :work_series
  has_many :work_genres, dependent: :destroy
  has_many :genres, through: :work_genres
  has_many :work_subjects, dependent: :destroy
  has_many :subjects, through: :work_subjects
  has_many :work_tags, dependent: :destroy
  has_many :tags, through: :work_tags
  has_many :work_awards, dependent: :destroy
  has_many :awards, through: :work_awards
  has_many :edition_contents, dependent: :destroy
  has_many :editions, through: :edition_contents
  has_many :readings, dependent: :restrict_with_error
  has_many :reviews, dependent: :restrict_with_error
  has_many :wishlist_items, dependent: :nullify
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :title, presence: true
end
