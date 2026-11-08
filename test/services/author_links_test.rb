require "test_helper"

class AuthorLinksTest < ActiveSupport::TestCase
  def author(name) = Contributor.create!(name:)

  def book(title, *authors, credits:, isfdb_title: title)
    work = Work.create!(title:, literary_form: "novel")
    authors.each { |a| work.work_contributors.create!(contributor: a, role: "author") }
    work.provider_editions.create!(provider: "isfdb", provider_id: "#{work.id}1", title: isfdb_title,
                                   author_names: credits.map(&:first), author_ids: credits.map(&:last))
    work
  end

  test "an author is linked through a book whose ISFDB printing credits them by name" do
    vinge = author("Joan D. Vinge")
    book("The Snow Queen", vinge, credits: [ [ "Joan D. Vinge", 60 ] ])

    assert_equal 1, AuthorLinks.run
    assert_equal [ "60", "books" ], [ vinge.reload.external_ids["isfdb"], vinge.field_sources["isfdb_id"] ]
  end

  test "a differently spelt sole author needs two books agreeing" do
    ballard = author("James Graham Ballard") # ISFDB credits him as J. G. Ballard
    book("The Drowned World", ballard, credits: [ [ "J. G. Ballard", 47 ] ])
    assert_equal 0, AuthorLinks.run

    book("Crash", ballard, credits: [ [ "J. G. Ballard", 47 ] ])
    assert_equal 1, AuthorLinks.run
    assert_equal "47", ballard.reload.external_ids["isfdb"]
  end

  test "co-written books link only by name; an omnibus's printing doesn't count; an existing link that disagrees is reported" do
    niven, pournelle = author("Larry Niven"), author("Jerry Pournelle")
    book("The Mote in God's Eye", niven, pournelle, credits: [ [ "Larry Niven", 1 ], [ "Jerry Pournelle", 2 ] ])
    book("Ringworld", niven, credits: [ [ "Larry Niven", 9 ] ], isfdb_title: "The Ringworld Omnibus")
    pournelle.update!(external_ids: { "isfdb" => "3" })

    links, disagreements = AuthorLinks.plan
    assert_equal [ [ niven, 1 ] ], links.map { |l| [ l.contributor, l.isfdb_id ] }
    assert_equal [ [ pournelle, 2, "3" ] ], disagreements.map { |l| [ l.contributor, l.isfdb_id, l.current ] }

    AuthorLinks.run
    assert_equal "3", pournelle.reload.external_ids["isfdb"]
  end
end
