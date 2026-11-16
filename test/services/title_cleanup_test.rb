require "test_helper"

class TitleCleanupTest < ActiveSupport::TestCase
  def book(title, main: nil, variants: [], sources: {})
    Work.create!(title:, literary_form: "novel", field_sources: sources, isfdb_main_title: main, isfdb_variant_titles: variants)
  end

  test "each difference from ISFDB's main title has a kind; all but a suspect link are applied" do
    worlds_end = book("World's End (Snow Queen Vol. 2)", main: "World's End")
    shadrach = book("Shadrach In The Furnace", main: "Shadrach in the Furnace")
    venus = book("Voyage to Venus", main: "Perelandra", variants: [ "Voyage to Venus" ])
    dispossessed = book("The Dispossessed: An Ambiguous Utopia", main: "The Dispossessed")
    kesrith = book("Kesrith", main: "The Faded Sun Trilogy", variants: [ "The Faded Sun" ])
    mine = book("Fury (U.K.)", main: "Fury", sources: { "title" => "manual" })
    book("Interzone #282 (July-August 2019)") # no main title fetched: nothing to compare

    kinds = TitleCleanup.plan.to_h { |f| [ f.work.id, f.kind ] }
    assert_equal({ worlds_end.id => :brackets, shadrach.id => :cosmetic, venus.id => :variant,
                   dispossessed.id => :reworded, kesrith.id => :suspect }, kinds)
    assert_not kinds.key?(mine.id)

    assert_equal 4, TitleCleanup.apply # all but the suspect link
    assert_equal [ "World's End", "isfdb" ], [ worlds_end.reload.title, worlds_end.field_sources["title"] ]
    assert_equal "Perelandra", venus.reload.title
    assert_equal [ "Voyage to Venus" ], venus.work_alternate_titles.pluck(:title) # still findable
    assert_equal "Kesrith", kesrith.reload.title # a suspect link is never retitled
  end

  test "a title Mark sets is his: marked manual, never listed again" do
    venus = book("Voyage to Venus", main: "Perelandra", variants: [ "Voyage to Venus" ])

    TitleCleanup.retitle(venus, "Voyage to Venus", source: "manual")

    assert_equal "manual", venus.reload.field_sources["title"]
    assert_empty TitleCleanup.plan
  end

  test "different volume numbers make it suspect; a title of no letters is ignored" do
    reader = book("The Astounding-Analog Reader, Book Two", main: "The Astounding-Analog Reader: Volume One",
                  variants: [ "The Astounding-Analog Reader, Book Two" ])
    nebula = book("Nebula Award Stories 2", main: "Nebula Award Stories Two")
    slant = book("Slant", main: "/")
    split = book("Dangerous Visions 1", main: "Dangerous Visions")

    kinds = TitleCleanup.plan.to_h { |f| [ f.work.id, f.kind ] }
    assert_equal :suspect, kinds[reader.id]
    assert_equal :reworded, kinds[nebula.id] # 2 and Two are the same number
    assert_not kinds.key?(slant.id)
    assert_equal :suspect, kinds[split.id] # a split volume linked to the whole
  end

  test "a split volume Mark linked to the whole book isn't suspect, nor one whose title he kept" do
    split = book("A Dance with Dragons 1: Dreams and Dust", main: "A Dance with Dragons")
    split.work_identifiers.create!(id_type: "isfdb_title", value: "867793", source: "manual")
    kept = book("The Hugo Winners 1955-1961", main: "The Hugo Winners")
    kept.update!(field_sources: { "title" => "manual" })

    assert_not TitleCleanup.suspect?(split.reload)
    assert_not TitleCleanup.suspect?(kept)
    assert_empty TitleCleanup.plan.select { |f| [ split.id, kept.id ].include?(f.work.id) }
  end

  test "a link from the printing an edition is set to isn't suspect" do
    work = book("Black Easter", main: "The Devil's Day")
    work.work_identifiers.create!(id_type: "isfdb_title", value: "688417", source: "isbn_lookup")
    assert TitleCleanup.suspect?(work.reload)

    edition = work.editions.create!(publisher: "Arrow Books", publish_date: "1981")
    edition.edition_identifiers.create!(id_type: "isfdb", value: "353524")
    ProviderEdition.create!(work:, provider: "isfdb", provider_id: "353524", title: "Black Easter / The Day After Judgment", provider_work_id: "688417")

    assert_not TitleCleanup.suspect?(Work.find(work.id))
    assert_equal 1, TitleCleanup.apply(Work.where(id: work.id))
    assert_equal "The Devil's Day", work.reload.title # the title follows the link, as any other
  end

  test "still suspect: a work linked to other records too, or a volume whose number differs" do
    cities = book("Cities in Flight", main: "The Triumph of Time")
    split = book("Dangerous Visions 2", main: "Dangerous Visions")
    [ [ cities, %w[100 101] ], [ split, %w[200] ] ].each do |work, links|
      links.each { |l| work.work_identifiers.create!(id_type: "isfdb_title", value: l, source: "isbn_lookup") }
      edition = work.editions.create!(publisher: "Arrow", publish_date: "1981")
      edition.edition_identifiers.create!(id_type: "isfdb", value: "p#{work.id}")
      ProviderEdition.create!(work:, provider: "isfdb", provider_id: "p#{work.id}", title: work.title, provider_work_id: links.first)
    end

    assert TitleCleanup.suspect?(Work.find(cities.id))
    assert TitleCleanup.suspect?(Work.find(split.id))
  end
end
