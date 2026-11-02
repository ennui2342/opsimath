# A wanted book: the want sits on its Work, so no edition is committed to
# before one is owned (docs/CATALOG.md, "Architecture review").
# Replaces the self-contained WishlistItem. Holds what Mark decides about
# hunting it — priority, notes, a target price, which covers he wants, a
# buy-new override — the ISBN(s) it was wanted under, which seed the
# provider lookups until the work has editions of its own, and the
# wishlist thumbnail the shop-lookup PWA shows.
class Want < ApplicationRecord
  # cover_url stays the source-of-record link; cover_image is the stored
  # copy the shop-lookup PWA needs a :thumb from (docs/MOBILE.md).
  include HasCoverThumbnail

  belongs_to :work

  validates :work_id, uniqueness: true

  # Want a book not yet in the catalogue: a new Work (literary form
  # "novel" unless known — the same default the Goodreads paths use), its
  # author, and the want. `isbns` are the ISBN(s) it's wanted under
  # (folded to ISBN-13); `series` optional.
  def self.add!(title:, author_name: nil, isbns: [], external_ids: {}, cover_url: nil, series: nil, literary_form: "novel")
    transaction do
      work = Work.create!(title:, literary_form:, field_sources: { "title" => external_ids["goodreads"] ? "goodreads" : "manual" })
      if author_name.present?
        contributor = Contributor.where("lower(name) = lower(?)", author_name).order(:id).first || Contributor.create!(name: author_name)
        work.work_contributors.create!(contributor:, role: "author", display_order: 0)
      end
      work.work_series.create!(series:) if series
      seeds = isbns.compact_blank.map { |i| i.length == 10 ? Isbn.to_13(i) : i }.compact.uniq
      create!(work:, seed_isbns: seeds, external_ids:, cover_url:)
    end
  end

  delegate :title, to: :work

  def author = work.authors.first

  def author_name = author&.name

  # :living / :dead / :unknown, from the author's ISFDB record
  # (ContributorLifeRefresh) — what CollectingProfile's buy-new rule reads.
  def author_status = author&.life_status || :unknown

  # Stop wanting the book. A Work that only existed for the want — no
  # editions, readings or reviews — goes with it (and its printings and
  # eBay listings), so no empty book is left in the catalogue; one that's
  # catalogued otherwise stays. `keep:` spares a work regardless (the one
  # a Goodreads to-read just catalogued the edition onto).
  def retire!(keep: nil)
    placeholder = work
    destroy!
    placeholder.destroy! if placeholder != keep && placeholder.editions.empty? &&
                            placeholder.readings.empty? && placeholder.reviews.empty?
  end

  # The work's ISFDB printings that bargain hunting reasons about: physical
  # ones (ebook/audio dropped).
  def printings = work.provider_editions.select(&:hunted_printing?)
end
