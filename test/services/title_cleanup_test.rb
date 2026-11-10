require "test_helper"

class TitleCleanupTest < ActiveSupport::TestCase
  def book(title, isfdb: nil, sources: {})
    work = Work.create!(title:, literary_form: "novel", field_sources: sources)
    work.provider_editions.create!(provider: "isfdb", provider_id: "#{work.id}1", title: isfdb) if isfdb
    work
  end

  test "differences from ISFDB's title: bracketed notes and cosmetic ones applied, different wording only listed" do
    worlds_end = book("World's End (Snow Queen Vol. 2)", isfdb: "World's End")
    traps = book("All the Traps of Earth (collection of stories)", isfdb: "All the Traps of Earth and Other Stories")
    shadrach = book("Shadrach In The Furnace", isfdb: "Shadrach in the Furnace")
    engines = book("Engines of God", isfdb: "The Engines of God")
    venus = book("Voyage to Venus", isfdb: "Perelandra")
    mine = book("Fury (U.K.)", isfdb: "Fury", sources: { "title" => "manual" })
    book("Interzone #282 (July-August 2019)") # no ISFDB title: nothing to compare

    kinds = TitleCleanup.plan.to_h { |f| [ f.work.id, f.kind ] }
    assert_equal({ worlds_end.id => :brackets, traps.id => :brackets, shadrach.id => :cosmetic, engines.id => :cosmetic, venus.id => :different }, kinds)
    assert_not kinds.key?(mine.id)

    assert_equal 4, TitleCleanup.apply
    assert_equal [ "World's End", "isfdb" ], [ worlds_end.reload.title, worlds_end.field_sources["title"] ]
    assert_equal "The Engines of God", engines.reload.title
    assert_equal "Voyage to Venus", venus.reload.title # left for Mark
    assert_equal "Retitled “World's End (Snow Queen Vol. 2)” to ISFDB's “World's End”", CatalogueEvent.where(work: worlds_end).sole.summary
  end

  test "a title Mark sets is his: marked manual, never listed again" do
    venus = book("Voyage to Venus", isfdb: "Perelandra")

    TitleCleanup.retitle(venus, "Voyage to Venus", source: "manual")

    assert_equal "manual", venus.reload.field_sources["title"]
    assert_empty TitleCleanup.plan
  end
end
