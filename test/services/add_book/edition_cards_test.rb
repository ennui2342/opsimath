require "test_helper"

module AddBook
  class EditionCardsTest < ActiveSupport::TestCase
    def ed(provider, id, **attrs) = Providers::Edition.new(provider:, id:, **attrs)

    test "ISFDB printings with the same publisher and cover share a card; Open Library joins by an unambiguous ISBN" do
      orbit79 = ed("isfdb", "2", publisher: "Orbit", publish_date: "1979", binding: "pb", cover_url: "https://c/jones.jpg", isbn10: "0860079422")
      orbit85 = ed("isfdb", "3", publisher: "Orbit", publish_date: "1985", binding: "pb", cover_url: "https://c/jones.jpg", isbn10: "0860079422")
      orbit77 = ed("isfdb", "1", publisher: "Orbit", publish_date: "1977", binding: "pb", cover_url: "https://c/dachille.jpg", isbn10: "0860079422")
      ol_reused = ed("openlibrary", "OL1M", publisher: "Futura", isbn10: "0860079422") # on two covers' cards: can't tell which
      ol_hc = ed("openlibrary", "OL4M", publisher: "Futura", isbn13: "9780708880005")
      isfdb_hc = ed("isfdb", "4", publisher: "Futura", binding: "hc", publish_date: "1977", cover_url: "https://c/hc.jpg", isbn13: "9780708880005")
      ol_tor = ed("openlibrary", "OL2M", publisher: "Tor", isbn13: "9780765304674")
      ol_tor_dup = ed("openlibrary", "OL3M", publisher: "Tom Doherty Associates", isbn13: "9780765304674")

      cards, hidden = EditionCards.build([ orbit79, orbit85, orbit77, isfdb_hc, ol_reused, ol_hc, ol_tor, ol_tor_dup ])

      assert_equal 0, hidden
      ids = cards.map { |c| c.editions.map(&:id).sort }
      assert_includes ids, %w[2 3]
      assert_includes ids, %w[4 OL4M]
      assert_includes ids, %w[OL1M]
      assert_includes ids, %w[OL2M OL3M]
      assert_equal [ "1979", "1985" ], cards.find { |c| c.editions.map(&:id).sort == %w[2 3] }.years
      assert_equal "Mass-market paperback", cards.find { |c| c.primary.id == "2" }.format_label
    end

    test "the same ISBN and cover artist under one publisher is one cover; the card's record has the cover and date" do
      dated = ed("isfdb", "1", publisher: "DAW Books", publish_date: "1975-11", binding: "pb", cover_url: "https://c/a.jpg",
                               cover_artist: "George Barr", isbn10: "0879971770")
      undated = ed("isfdb", "2", publisher: "DAW Books", binding: "pb", cover_url: "https://c/b.jpg", cover_artist: "George Barr", isbn10: "0879971770")
      other_art = ed("isfdb", "3", publisher: "DAW Books", binding: "pb", cover_artist: "Ken W. Kelly", isbn10: "0879971770")

      cards, = EditionCards.build([ undated, dated, other_art ])

      assert_equal [ %w[1 2], %w[3] ], cards.map { |c| c.editions.map(&:id).sort }
      assert_equal "1", cards.first.primary.id
    end

    test "other languages are hidden unless asked for; ebooks come after physical books" do
      german = ed("openlibrary", "OL9M", publisher: "Bastei Lübbe", language: "ger")
      ebook = ed("isfdb", "5", publisher: "Gollancz", binding: "ebook", publish_date: "1960")
      paper = ed("isfdb", "6", publisher: "Pan", binding: "pb", publish_date: "1978")

      cards, hidden = EditionCards.build([ german, ebook, paper ])
      assert_equal 1, hidden
      assert_equal %w[6 5], cards.map { |c| c.primary.id }

      all, = EditionCards.build([ german, ebook, paper ], all_languages: true)
      assert_equal 3, all.size
    end

    test "a catalogued work's known editions become provider records" do
      work = Work.create!(title: "W", literary_form: "novel")
      work.provider_editions.create!(provider: "isfdb", provider_id: "7", binding: "pb", publisher: "Pan")

      assert_equal [ [ "isfdb", "7", "Pan" ] ], EditionCards.from_provider_editions(work.provider_editions).map { |e| [ e.provider, e.id, e.publisher ] }
    end
  end
end
