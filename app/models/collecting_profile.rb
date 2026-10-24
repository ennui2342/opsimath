# What Mark collects, as a rule over a wishlist book's ISFDB printings
# (docs/BARGAIN_HUNTING.md, "What counts as wanted"). A single row.
#
# Format first, then cover art: Mark collects paperbacks for their covers
# and artists, not for being early printings, so any year will do.
#
# - An item with printing_override_ids wants exactly those printings.
# - A book with an A-format printing wants all its A-formats.
# - A book with no A-format, if it's recent (first published within
#   recent_years) or its author is alive, is *buy new* — not hunted, so
#   the author is paid. buy_new_override forces this either way.
# - Otherwise (an older book by a dead author, never in A-format) it
#   wants its B-formats (ISFDB `tp`), or any physical printing if it was
#   never paperbacked at all.
# - A book ISFDB has no printings for is hunted unless its author is
#   alive or unknown — then it's buy new — with every listing's printing
#   unknown.
# - Book club editions are never wanted.
#
# An author ISFDB can't identify counts as living: the default leans
# towards paying the author.
class CollectingProfile < ApplicationRecord
  Verdict = Struct.new(:rule, :wanted, :first_year, keyword_init: true) do
    def wanted?(printing) = wanted.include?(printing)

    def hunt? = rule != :buy_new
  end

  def self.current = first || create!

  def verdict(item, printings = item.wishlist_printings.to_a)
    first_year = printings.filter_map(&:year).min
    verdict = ->(rule, wanted = []) { Verdict.new(rule:, wanted:, first_year:) }

    if item.printing_override_ids
      return verdict.(:override, printings.select { |p| item.printing_override_ids.include?(p.isfdb_pub_id) })
    end

    eligible = printings.reject(&:book_club?)
    a_formats = eligible.select(&:a_format?)
    return verdict.(:a_format, a_formats) if a_formats.any?
    return verdict.(:buy_new) if buy_new?(item, first_year)
    return verdict.(:unknown_printings) if printings.empty?

    b_formats = eligible.select(&:b_format?)
    b_formats.any? ? verdict.(:b_format, b_formats) : verdict.(:no_paperback, eligible)
  end

  # Artists on at least favourite_artist_min_owned of Mark's owned
  # editions, plus the always list, minus the never list. Worked out from
  # the collection on every call, so it keeps up as books are catalogued
  # (and their cover artists filled in by ISFDB enrichment) with nothing
  # to maintain but the two exception lists.
  def favourite_artists
    owned = Copy.where(disposition: "owned").select(:edition_id)
    counts = Edition.where(id: owned).where.not(cover_artist: [ nil, "" ])
                    .pluck(:cover_artist).flat_map { |a| a.split(", ") }.tally
    (counts.select { |_, n| n >= favourite_artist_min_owned }.keys | favourite_artists_always) - favourite_artists_never
  end

  # An unknown year isn't recent — the author's status decides those.
  def recent?(year) = year.present? && year >= Date.current.year - recent_years

  private

  def buy_new?(item, first_year)
    return item.buy_new_override unless item.buy_new_override.nil?

    item.author_status != :dead || recent?(first_year)
  end
end
