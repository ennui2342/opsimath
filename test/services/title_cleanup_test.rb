require "test_helper"

class TitleCleanupTest < ActiveSupport::TestCase
  def book(title, main: nil, variants: [], sources: {})
    Work.create!(title:, literary_form: "novel", field_sources: sources, isfdb_main_title: main, isfdb_variant_titles: variants)
  end

  test "each difference from ISFDB's main title has a kind; only the automatic kinds are applied" do
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

    assert_equal 2, TitleCleanup.apply
    assert_equal [ "World's End", "isfdb" ], [ worlds_end.reload.title, worlds_end.field_sources["title"] ]
    assert_equal "Voyage to Venus", venus.reload.title # not automatic (yet)

    TitleCleanup.apply(kinds: %i[variant])
    assert_equal "Perelandra", venus.reload.title
    assert_equal [ "Voyage to Venus" ], venus.work_alternate_titles.pluck(:title) # still findable
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
end
