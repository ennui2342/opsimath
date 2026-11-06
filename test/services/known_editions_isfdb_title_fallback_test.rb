require "test_helper"

# A book with no usable ISBN, found by title + author through the provider's
# own search (KnownEditionsRefresh#by_title + WorkMatcher) — here, ISFDB.
class KnownEditionsIsfdbTitleFallbackTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:search_results, :editions_by_isbn, :searched) do
    def search(query, **) = (self.searched = query) && search_results
    def lookup_editions(isbn) = editions_by_isbn.fetch(isbn, [])
    def lookup_isbn(_isbn) = []
  end

  def pub(id, title_id, title, author, isbn = nil, extra = {})
    { "_isfdb_pub_id" => id, "_isfdb_title_id" => title_id, "title" => title, "authors" => [ author ], "isbn_13" => isbn, "language" => "eng" }.merge(extra)
  end

  setup do
    @work = Work.create!(title: "The Fifth Head of Cerberus", literary_form: "novel")
    @work.work_contributors.create!(contributor: Contributor.create!(name: "Gene Wolfe"), role: "author")
    edition = Edition.create!(publisher: "Gollancz") # no ISBN: only a Goodreads id
    EditionContent.create!(work: @work, edition:)
    edition.edition_identifiers.create!(id_type: "goodreads", value: "29416510")
    @full = [ pub(1, 1957, "The Fifth Head of Cerberus", "Gene Wolfe", "9780684128306", "publisher" => "Scribner's"),
              pub(2, 1957, "The Fifth Head of Cerberus", "Gene Wolfe", "9780575015975", "publisher" => "Gollancz") ]
  end

  def refresh(client)
    KnownEditionsRefresh.new(provider: Providers::Isfdb.new(client:)).refresh_one(Work.includes(:want, { work_contributors: :contributor }, editions: :edition_identifiers).find(@work.id))
  end

  test "a work with no ISBN is found by its one matching title and author, with that title's printings" do
    client = FakeClient.new(@full + [ pub(9, 3219545, "The Wolfe at the Door", "Gene Wolfe") ], {})

    refresh(client)

    assert_equal "The Fifth Head of Cerberus Gene Wolfe", client.searched
    assert_equal %w[1 2], @work.provider_editions.order(:provider_id).pluck(:provider_id)
    assert_equal [ "1957" ], @work.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
  end

  test "no title by this author: nothing is guessed" do
    refresh(FakeClient.new([ pub(7, 77, "The Fifth Head of Cerberus", "Someone Else") ], {}))

    assert_empty @work.provider_editions
  end

  test "a same-titled translation, or an adaptation, doesn't make it ambiguous" do
    translation = pub(8, 1776893, "Lexicon", "Max Barry", nil, "language" => "ger")
    english = pub(9, 1588162, "Lexicon", "Max Barry", "9781444764680", "language" => "eng")
    @work.update!(title: "Lexicon")
    @work.work_contributors.sole.contributor.update!(name: "Max Barry")
    refresh(FakeClient.new([ translation, english ], {}))
    assert_equal [ "1588162" ], @work.work_identifiers.where(id_type: "isfdb_title").pluck(:value)

    kindred = Work.create!(title: "Kindred", literary_form: "novel")
    kindred.work_contributors.create!(contributor: Contributor.create!(name: "Octavia E. Butler"), role: "author")
    novel = pub(10, 1669, "Kindred", "Octavia E. Butler", "9781472258229")
    graphic = pub(11, 2837240, "Kindred: A Graphic Novel Adaptation", "Octavia E. Butler")
    KnownEditionsRefresh.new(provider: Providers::Isfdb.new(client: FakeClient.new([ graphic, novel ], {})))
                        .refresh_one(Work.includes(:want, { work_contributors: :contributor }, editions: :edition_identifiers).find(kindred.id))
    assert_equal [ "1669" ], kindred.work_identifiers.where(id_type: "isfdb_title").pluck(:value)
    assert_equal [ "10" ], kindred.provider_editions.pluck(:provider_id)
  end

  test "the same book credited two ways is one book; a different volume is not" do
    @work.update!(title: "The Paradise Game")
    @work.work_contributors.sole.contributor.update!(name: "Brian M. Stableford")
    refresh(FakeClient.new([ pub(1, 245541, "The Paradise Game", "Brian M. Stableford"), pub(2, 6719, "The Paradise Game", "Brian Stableford") ], {}))
    assert_equal %w[1 2], @work.provider_editions.order(:provider_id).pluck(:provider_id)

    vol2 = Work.create!(title: "The Past Through Tomorrow: Vol. 2", literary_form: "novel")
    vol2.work_contributors.create!(contributor: Contributor.create!(name: "Robert A. Heinlein"), role: "author")
    KnownEditionsRefresh.new(provider: Providers::Isfdb.new(client: FakeClient.new([
      pub(3, 2033368, "The Past Through Tomorrow: Vol. 1", "Robert A. Heinlein"), pub(4, 2609142, "The Past Through Tomorrow: Book One", "Robert A. Heinlein")
    ], {}))).refresh_one(Work.includes(:want, { work_contributors: :contributor }, editions: :edition_identifiers).find(vol2.id))
    assert_empty vol2.provider_editions
  end
end
