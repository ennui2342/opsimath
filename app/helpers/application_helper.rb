module ApplicationHelper
  # Marks every find card on one cover of one book, so "Not this cover"
  # can remove them all at once.
  def find_cover_class(want, cover_id) = "find-cover-#{want.id}-#{cover_id}"
end
