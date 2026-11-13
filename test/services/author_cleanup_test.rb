require "test_helper"

class AuthorCleanupTest < ActiveSupport::TestCase
  def book(title, *names, isfdb:)
    work = Work.create!(title:, literary_form: "novel")
    work.work_identifiers.create!(id_type: "isfdb_title", value: isfdb.to_s)
    names.each_with_index do |name, i|
      person = Contributor.find_by(name:) || Contributor.create!(name:)
      work.work_contributors.create!(contributor: person, role: "author", display_order: i)
    end
    work
  end

  def title(id, name, authors, aliases: [])
    stub_request(:get, "#{ENV.fetch("ISFDB_ADAPTER_URL")}/titles/#{id}").to_return(status: 200, body: {
      id:, title: name, type: "NOVEL", variants: [],
      main: { id:, title: name, type: "NOVEL", authors: authors.map { |i, n| { id: i.to_s, name: n } },
              author_aliases: aliases.map { |i, n, of| { id: i.to_s, name: n, of: of.map(&:to_s) } } }
    }.to_json)
  end

  def roles(work) = work.reload.work_contributors.includes(:contributor).map { |wc| [ wc.contributor.name, wc.role ] }.sort

  test "a translator and an introducer stay on the book as contributors; a reordered name is the same author" do
    work = book("The Wandering Earth", "Liu Cixin", "Ken Liu", "Adam Lanphier", isfdb: 10)
    title(10, "The Wandering Earth", [ [ 77, "Cixin Liu" ] ])

    _, changes = AuthorCleanup.plan
    assert_equal [ "Adam Lanphier", "Ken Liu" ], changes.sole.demote.map(&:name).sort

    AuthorCleanup.apply
    assert_equal [ [ "Adam Lanphier", "contributor" ], [ "Ken Liu", "contributor" ], [ "Liu Cixin", "author" ] ], roles(work)
    assert_equal "77", Contributor.find_by(name: "Liu Cixin").external_ids["isfdb"]
  end

  test "a pseudonym the title is credited under counts as its author; a missing co-author is added" do
    work = book("Mutant", "Henry Kuttner", isfdb: 20)
    title(20, "Mutant", [ [ 1, "Henry Kuttner" ], [ 2, "C. L. Moore" ] ], aliases: [ [ 3, "Lewis Padgett", [ 1, 2 ] ] ])

    AuthorCleanup.apply
    assert_equal [ [ "C. L. Moore", "author" ], [ "Henry Kuttner", "author" ] ], roles(work)

    work2 = book("Exiles on Asperus", "John Beynon", isfdb: 21)
    title(21, "Exiles on Asperus", [ [ 5, "John Wyndham" ] ], aliases: [ [ 6, "John Beynon", [ 5 ] ] ])
    _, changes = AuthorCleanup.new(works: Work.where(id: work2.id)).plan
    assert_empty changes
  end

  test "a mangled name is replaced by ISFDB's credits" do
    work = book("Oath of Fealty", "Larry & Jerry Niven & Pournelle", isfdb: 30)
    Contributor.create!(name: "Larry Niven")
    title(30, "Oath of Fealty", [ [ 8, "Larry Niven" ], [ 9, "Jerry Pournelle" ] ])

    AuthorCleanup.apply
    assert_equal [ [ "Jerry Pournelle", "author" ], [ "Larry Niven", "author" ] ], roles(work)
    assert_equal 1, Contributor.where(name: "Larry Niven").count
  end

  test "the same person twice is merged into the well-formed name" do
    good = Contributor.create!(name: "C.J. Cherryh", external_ids: { "isfdb" => "16" })
    slug = Contributor.create!(name: "c-j-cherryh", external_ids: { "isfdb" => "16" })
    a = Work.create!(title: "Cyteen", literary_form: "novel")
    b = Work.create!(title: "Downbelow Station", literary_form: "novel")
    a.work_contributors.create!(contributor: good, role: "author")
    b.work_contributors.create!(contributor: slug, role: "author")
    Contributor.create!(name: "Ben Smith", external_ids: { "isfdb" => "1" })
    Contributor.create!(name: "Ben Smith", external_ids: { "isfdb" => "2" }) # two people, one name

    merged, = AuthorCleanup.apply

    assert_equal 1, merged
    assert_not Contributor.exists?(slug.id)
    assert_equal [ good ], b.reload.work_contributors.map(&:contributor)
    assert_equal 2, Contributor.where(name: "Ben Smith").count
  end

  test "a book on a suspect ISFDB link is left alone" do
    work = book("The Adventures of Alyx", "Joanna Russ", isfdb: 40)
    work.update!(isfdb_main_title: "Picnic on Paradise")
    title(40, "Picnic on Paradise", [ [ 1, "Someone Else" ] ])

    _, changes = AuthorCleanup.plan
    assert_empty changes
  end

  test "names: order, accents, Jr. and initials agree; a different first name doesn't" do
    assert AuthorCleanup.same?("Kurt Vonnegut Jr.", "Kurt Vonnegut")
    assert AuthorCleanup.same?("Stanisław Lem", "Stanislaw Lem")
    assert AuthorCleanup.same?("Brian M. Stableford", "Brian Stableford")
    assert AuthorCleanup.same?("Ben Smith", AuthorCleanup.clean("Ben Smith (I)"))
    assert_not AuthorCleanup.same?("Christopher Tolkien", "J. R. R. Tolkien")
    assert_not AuthorCleanup.same?("Ken Liu", "Cixin Liu")
  end
end
