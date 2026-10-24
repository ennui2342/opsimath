require "test_helper"

class CollectingProfileTest < ActiveSupport::TestCase
  setup do
    @profile = CollectingProfile.new(recent_years: 5, favourite_artist_min_owned: 2)
    @item = WishlistItem.create!(title: "The Birthgrave", author_name: "Tanith Lee")
  end

  def printing(pub_id, binding, date, publisher = "Orbit", artist: nil)
    @item.wishlist_printings.create!(isfdb_pub_id: pub_id, binding:, publish_date: date, publisher:, cover_artist: artist)
  end

  def dead! = @item.update!(author_isfdb_id: 1, author_died_date: "2015-05-24")
  def living! = @item.update!(author_isfdb_id: 1, author_died_date: nil)

  test "a book with A-formats wants every A-format, of any year" do
    living!
    hc = printing(1, "hc", "1975-06", "DAW Books")
    pb75 = printing(2, "pb", "1975-06", "DAW Books")
    pb15 = printing(3, "pb", "2015-06-02", "DAW Books")
    tp = printing(4, "tp", "2010")

    verdict = @profile.verdict(@item)

    assert_equal :a_format, verdict.rule
    assert_equal [ pb75, pb15 ], verdict.wanted.sort_by(&:isfdb_pub_id)
    [ hc, tp ].each { |p| assert_not verdict.wanted?(p) }
    assert verdict.hunt?
  end

  test "no A-format and the author is alive: buy new" do
    living!
    printing(1, "hc", "1990")
    printing(2, "tp", "1991")

    verdict = @profile.verdict(@item)

    assert_equal :buy_new, verdict.rule
    assert_empty verdict.wanted
    assert_not verdict.hunt?
  end

  test "no A-format and a recent book: buy new, even if the author has died" do
    dead!
    printing(1, "hc", (Date.current.year - 2).to_s)

    assert_equal :buy_new, @profile.verdict(@item).rule
  end

  test "an author ISFDB can't identify counts as living" do
    printing(1, "tp", "1990")

    assert_equal :unknown, @item.author_status
    assert_equal :buy_new, @profile.verdict(@item).rule
  end

  test "no A-format, older book, author dead: B-formats are wanted" do
    dead!
    hc = printing(1, "hc", "1987")
    tp = printing(2, "tp", "1988")

    verdict = @profile.verdict(@item)

    assert_equal :b_format, verdict.rule
    assert_equal [ tp ], verdict.wanted
    assert_not verdict.wanted?(hc)
  end

  test "never paperbacked, older book, author dead: any physical printing" do
    dead!
    hc = printing(1, "hc", "1987")

    verdict = @profile.verdict(@item)

    assert_equal :no_paperback, verdict.rule
    assert_equal [ hc ], verdict.wanted
  end

  test "the buy-new override wins either way" do
    living!
    tp = printing(1, "tp", "1990")
    @item.buy_new_override = false
    assert_equal [ tp ], @profile.verdict(@item).wanted

    dead!
    @item.buy_new_override = true
    assert_equal :buy_new, @profile.verdict(@item).rule
  end

  test "no ISFDB printings: hunted if the author is dead, buy new otherwise" do
    dead!
    assert_equal :unknown_printings, @profile.verdict(@item).rule
    assert @profile.verdict(@item).hunt?

    living!
    assert_equal :buy_new, @profile.verdict(@item).rule
  end

  test "book club editions are never wanted, and don't count as an A-format" do
    living!
    club_pb = printing(1, "pb", "1980", "Readers Union / The Science Fiction Book Club (UK)")
    printing(2, "hc", "1980", "Harper & Row / BCE")

    verdict = @profile.verdict(@item)

    assert_equal :buy_new, verdict.rule
    assert_not verdict.wanted?(club_pb)
  end

  test "an override wants exactly the chosen printings" do
    printing(1, "pb", "1977")
    chosen = printing(2, "tp", "2015")
    @item.update!(printing_override_ids: [ 2 ])

    verdict = @profile.verdict(@item)

    assert_equal :override, verdict.rule
    assert_equal [ chosen ], verdict.wanted
  end

  test "favourite artists come from the owned collection, adjusted by the always and never lists" do
    own = ->(artist, disposition: "owned") do
      edition = Edition.create!(format: "paperback", cover_artist: artist)
      Copy.create!(edition:, disposition:)
    end
    own.("Chris Moore")
    own.("Chris Moore, Jim Burns")
    own.("Jim Burns", disposition: "sold")
    own.("Blacksheep")
    own.("Blacksheep")

    assert_equal %w[Blacksheep Chris\ Moore].sort, @profile.favourite_artists.sort

    profile = CollectingProfile.new(favourite_artist_min_owned: 2, favourite_artists_always: [ "Bruce Pennington" ],
                                    favourite_artists_never: [ "Blacksheep" ])
    @profile = profile
    assert_equal [ "Bruce Pennington", "Chris Moore" ], @profile.favourite_artists.sort
  end
end
