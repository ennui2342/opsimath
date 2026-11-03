require "test_helper"

class KnownEditionsIsfdbTitleFallbackTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:search_results, :editions_by_isbn, :searched) do
    def search(query, **) = (self.searched = query) && search_results
    def lookup_editions(isbn) = editions_by_isbn.fetch(isbn, [])
    def lookup_isbn(_isbn) = []
  end

  def pub(id, title_id, title, author, isbn = nil, **attrs)
    { "_isfdb_pub_id" => id, "_isfdb_title_id" => title_id, "title" => title, "authors" => [ author ], "isbn_13" => isbn }.merge(attrs)
  end

  setup do
    @work = Work.create!(title: "The Fifth Head of Cerberus", literary_form: "novel")
    @work.work_contributors.create!(contributor: Contributor.create!(name: "Gene Wolfe"), role: "author")
    edition = Edition.create!(publisher: "Gollancz") # no ISBN: only a Goodreads id
    EditionContent.create!(work: @work, edition:)
    edition.edition_identifiers.create!(id_type: "goodreads", value: "29416510")
    @full = [ pub(1, 1957, "The Fifth Head of Cerberus", "Gene Wolfe", "9780684128306", publisher: "Scribner's"),
              pub(2, 1957, "The Fifth Head of Cerberus", "Gene Wolfe", "9780575015975", publisher: "Gollancz") ]
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

  test "several titles matching, or none: nothing is guessed" do
    other = pub(5, 4242, "The Fifth Head of Cerberus", "Gene Wolfe", "9780000000002")
    refresh(FakeClient.new([ @full.first, other ], {}))
    assert_empty @work.provider_editions

    refresh(FakeClient.new([ pub(7, 77, "The Fifth Head of Cerberus", "Someone Else") ], {}))
    assert_empty @work.provider_editions
  end
end
