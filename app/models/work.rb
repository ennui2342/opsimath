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
  has_many :work_identifiers, dependent: :destroy
  # The editions providers know for this work — candidates, not the
  # catalogue's own `editions` (docs/CATALOG.md, "Architecture review").
  has_many :provider_editions, dependent: :destroy
  has_many :provider_edition_refreshes, dependent: :destroy
  # Wanted (docs/CATALOG.md): bargain hunting's book, its eBay listings.
  has_one :want, dependent: :destroy
  has_many :ebay_listings, dependent: :destroy
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
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :title, presence: true

  # The work's authors in credit order (role "author"), as the shop app's
  # snapshot lists them.
  def authors
    work_contributors.select { |wc| wc.role == "author" }
                     .sort_by { |wc| wc.display_order || Float::INFINITY }
                     .map(&:contributor)
  end

  # Where the book stands for Mark, for the Books list and the book page:
  # any of :owned, :wanted, :reading, :read, :dnf.
  # The book's editions as the book page lists them: the ones Mark owns
  # first, then the rest, each newest to the catalogue first — so what's
  # on his shelf now leads.
  def editions_in_order
    editions.sort_by { |e| [ EditionHolding.status(e) == "owned" ? 0 : 1, -e.created_at.to_f, -e.id ] }
  end

  def statuses
    list = []
    list << :owned if editions.any? { |e| e.copies.any?(&:owned?) }
    list << :wanted if want
    list << :reading if readings.any?(&:open?)
    list << :read if readings.any?(&:completed?)
    list << :dnf if readings.any?(&:dnf?) && readings.none?(&:completed?)
    list
  end
end
