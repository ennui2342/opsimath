class Contributor < ApplicationRecord
  has_paper_trail

  has_many :work_contributors, dependent: :destroy
  has_many :edition_contributors, dependent: :destroy
  has_many :works, through: :work_contributors
  has_many :editions, through: :edition_contributors
  has_many :enrichment_records, as: :entity, dependent: :destroy

  validates :name, presence: true

  # :living / :dead from the ISFDB author record (ContributorLifeRefresh),
  # :unknown when it couldn't be identified — CollectingProfile's buy-new
  # rule treats unknown as living. died_date is EDTF.
  def life_status
    return :dead if died_date.present?

    external_ids["isfdb"].present? ? :living : :unknown
  end

  # One of the author's other names (ISFDB's pseudonym links): the person
  # in the catalogue under it, if any; ISFDB's author id either way.
  OtherName = Struct.new(:name, :isfdb_id, :contributor, keyword_init: true)

  # Names this one belongs to — Claire North is a pen name of Catherine
  # Webb — not counting another form of the same name ("Iain Banks" is
  # filed under "Iain M. Banks"), which is `published_as`.
  def pen_name_of = other_names("pseudonym_of").reject { |o| same_person?(o.name) }

  # The author's other names, and other forms of this one (Catherine Webb:
  # Claire North, Kate Griffin; Iain Banks: Iain M. Banks) — those that
  # matter here: someone in the catalogue under it, or one of its books'
  # ISFDB printings credited to it. ISFDB records every variant ever seen
  # (Wyndham: "Džon Vindhem", "L. Parkes"); John Beynon Harris and Lucas
  # Parkes are the ones on his books.
  def published_as
    names = (other_names("pseudonyms") + other_names("pseudonym_of").select { |o| same_person?(o.name) }).uniq(&:isfdb_id)
    return names if names.empty?

    credited = ProviderEdition.where(provider: "isfdb").where("author_ids && ARRAY[?]::integer[]", names.map { |o| o.isfdb_id.to_i })
                              .pluck(:author_ids).flatten.to_set
    # Another spelling of this very name ("Ursula Le Guin", ISFDB's misprint
    # "Bruce Stirling") is only worth a link to its own page here.
    names.select { |o| o.contributor || (credited.include?(o.isfdb_id.to_i) && !same_person?(o.name)) }
  end

  private

  # Latin-script names only: ISFDB's canonical name for a Russian or
  # Japanese author is in their script, and this one (Arkady Strugatsky)
  # is filed as its "pseudonym" — the same person, nothing to say.
  def other_names(key)
    rows = Array(isfdb_names&.dig(key)).map { |r| r.merge("name" => CGI.unescapeHTML(r["name"].to_s)) }
                                       .select { |r| r["name"].match?(/\A[\p{Latin}\p{Common}\p{Inherited}]+\z/) }
                                       .reject { |r| r["name"].include?("(in error)") } # ISFDB's misattributions
    people = Contributor.where("external_ids->>'isfdb' IN (?)", rows.map { |r| r["id"].to_s }.presence || [ "" ])
                        .index_by { |c| c.external_ids["isfdb"] }
    rows.map { |r| OtherName.new(name: r["name"], isfdb_id: r["id"].to_s, contributor: people[r["id"].to_s]) }
  end

  HONORIFICS = /\b(sir|dr|st|m\.?\s?d|ph\.?\s?d)\b\.?,?/i

  # The same name: AuthorCleanup's test, after titles and honorifics
  # ("Sir Thomas More", "David H. Keller, M.D."), or with an initial more
  # or less ("K. Eric Drexler").
  def same_person?(other)
    a, b = [ name, other ].map { |n| n.gsub(HONORIFICS, " ").squeeze(" ").strip }
    return true if AuthorCleanup.same?(a, b)

    ta, tb = AuthorCleanup.tokens(a), AuthorCleanup.tokens(b)
    ta.last == tb.last && ((ta - tb).empty? || (tb - ta).empty?)
  end
end
