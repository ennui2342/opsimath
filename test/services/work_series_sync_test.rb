require "test_helper"

class WorkSeriesSyncTest < ActiveSupport::TestCase
  setup do
    @cycle = Series.create!(name: "The Snow Queen Cycle") # from the Goodreads import
    @summer = book("The Summer Queen", series_num: 3)
    WorkSeries.create!(work: @summer, series: @cycle, position: 3)
    @snow = book("The Snow Queen", series_num: 1)
    @worlds_end = book("World's End (Snow Queen Vol. 2)", isfdb_title: "World's End", series_num: 2)
  end

  def book(title, series_num:, isfdb_title: title, series_name: "The Snow Queen Cycle", series_id: 448)
    work = Work.create!(title:, literary_form: "novel")
    work.provider_editions.create!(provider: "isfdb", provider_id: "#{work.id}01", title: isfdb_title, binding: "pb",
                                   series_id:, series_name:, series_num:)
    work
  end

  test "files books in the series of the same name, with ISFDB's number, and ties it to ISFDB" do
    assert_equal [ [ "The Snow Queen", 1 ], [ "World's End (Snow Queen Vol. 2)", 2 ] ],
                 WorkSeriesSync.plan.map { |c| [ c.work.title, c.position.to_i ] }.sort

    assert_equal 2, WorkSeriesSync.run

    assert_equal [ [ @cycle.id, 1 ] ], @snow.work_series.reload.map { |ws| [ ws.series_id, ws.position.to_i ] }
    assert_equal 448, @cycle.reload.isfdb_series_id
    assert_equal "The Snow Queen: in The Snow Queen Cycle #1 (from ISFDB)", CatalogueEvent.where(kind: "series").order(:id).first.summary
    assert_equal 0, WorkSeriesSync.run # nothing more to do
  end

  test "never changes a position that's there; fills an empty one" do
    WorkSeries.create!(work: @snow, series: @cycle, position: 0.5)
    @summer.work_series.first.update!(position: nil)

    WorkSeriesSync.run

    assert_equal 0.5, @snow.work_series.reload.first.position
    assert_equal 3, @summer.work_series.reload.first.position
  end

  test "a series not yet in the catalogue is created; an omnibus's printing doesn't count" do
    tales = book("Tales of the Snow Queen", series_num: nil, series_name: "Tales of the Snow Queen", series_id: 39037)
    omnibus = Work.create!(title: "The Snow Queen", literary_form: "novel")
    omnibus.provider_editions.create!(provider: "isfdb", provider_id: "999", title: "The Snow Queen Omnibus", series_id: 7, series_name: "Omnibuses")

    WorkSeriesSync.run

    assert_equal [ [ "Tales of the Snow Queen", 39037, nil ] ], tales.work_series.reload.map { |ws| [ ws.series.name, ws.series.isfdb_series_id, ws.position ] }
    assert_not Series.exists?(name: "Omnibuses")
  end

  test "without ISFDB's series name there's nothing to match or create yet" do
    @snow.provider_editions.update_all(series_name: nil)
    @worlds_end.provider_editions.update_all(series_name: nil)

    assert_equal 0, WorkSeriesSync.run
  end

  test "a series under a shorter name is the same one when all its books are in that ISFDB series; a parent series isn't" do
    confluence = Series.create!(name: "Confluence")
    ancients = book("Ancients of Days", series_num: 2, series_name: "The Book of Confluence", series_id: 900)
    WorkSeries.create!(work: ancients, series: confluence, position: 2)
    shrine = book("Shrine of Stars", series_num: 3, series_name: "The Book of Confluence", series_id: 900)

    discworld = Series.create!(name: "Discworld")
    WorkSeries.create!(work: book("Mort", series_num: 1, series_name: "Death", series_id: 50), series: discworld, position: 4)
    reaper = book("Reaper Man", series_num: 2, series_name: "Death", series_id: 50)

    WorkSeriesSync.run

    assert_equal [ [ confluence.id, 3 ] ], shrine.work_series.reload.map { |ws| [ ws.series_id, ws.position.to_i ] }
    assert_equal 900, confluence.reload.isfdb_series_id
    assert_equal [ "Death" ], reaper.work_series.reload.map { |ws| ws.series.name } # its own series, not Discworld
  end
end
