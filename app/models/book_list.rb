# A reading list (docs/LISTS.md): one award category from ISFDB (every
# year's winner and shortlist) or a fixed published list (Pringle 100).
class BookList < ApplicationRecord
  has_many :entries, -> { order(:year, :position, :id) }, class_name: "BookListEntry", dependent: :delete_all
  has_one :book_list_want, dependent: :destroy

  validates :key, :name, :short_name, :kind, presence: true
  validates :kind, inclusion: { in: %w[award curated] }

  def award? = kind == "award"
end
