require "test_helper"

class TitleCleanupTest < ActiveSupport::TestCase
  def book(title, isfdb: nil, sources: {})
    work = Work.create!(title:, literary_form: "novel", field_sources: sources)
    work.provider_editions.create!(provider: "isfdb", provider_id: "#{work.id}1", title: isfdb) if isfdb
    work
  end

  test "bracketed series and imprint text goes when ISFDB's title is the same book's title" do
    worlds_end = book("World's End (Snow Queen Vol. 2)", isfdb: "World's End")
    recalled = book("Recalled to life (Panther science fiction)", isfdb: "Recalled to Life")
    traps = book("All the Traps of Earth (collection of stories)", isfdb: "All the Traps of Earth and Other Stories")
    middles = book("Beginnings, Middles & Ends (Elements of Fiction Writing)", isfdb: "Beginnings, Middles and Ends")
    interzone = book("Interzone #282 (July-August 2019)")
    other = book("Clarion (I)", isfdb: "The Clarion Anthology")
    mine = book("Fury (U.K.)", isfdb: "Fury", sources: { "title" => "manual" })

    fixes, rest = TitleCleanup.plan
    assert_equal [ worlds_end, recalled, traps, middles ].map(&:id).sort, fixes.map { |f| f.work.id }.sort
    assert_equal [ interzone, other, mine ].map(&:id).sort, rest.map(&:id).sort

    assert_equal 4, TitleCleanup.apply
    assert_equal [ "World's End", "isfdb" ], [ worlds_end.reload.title, worlds_end.field_sources["title"] ]
    assert_equal "Recalled to Life", recalled.reload.title
    assert_equal "Retitled “World's End (Snow Queen Vol. 2)” to ISFDB's “World's End”", CatalogueEvent.where(work: worlds_end).sole.summary
  end
end
