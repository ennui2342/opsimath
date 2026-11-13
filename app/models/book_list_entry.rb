# One book on a list: as the list gives it (title, author, year), its
# standing (winner, shortlisted, or just listed), and its ISFDB title.
class BookListEntry < ApplicationRecord
  belongs_to :book_list

  validates :status, inclusion: { in: %w[winner shortlisted listed] }

  def winner? = status == "winner"

  # A collecting scope of "winners" takes a curated list's entries too —
  # every one of them is the pick.
  def in_scope?(scope) = scope == "shortlist" || status != "shortlisted"
end
