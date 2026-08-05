class GoodreadsSyncState < ApplicationRecord
  validates :goodreads_book_id, presence: true
  validates :shelf, presence: true
end
