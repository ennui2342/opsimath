require "test_helper"

module Ui
  class BookMastheadComponentTest < ViewComponent::TestCase
    setup do
      @le_guin = Contributor.create!(name: "Ursula K. Le Guin", died_date: "2018-01-22")
      @editor = Contributor.create!(name: "Brian Attebery")
      @work = Work.create!(title: "The Left Hand of Darkness", subtitle: "A Novel", literary_form: "novel")
      @work.work_contributors.create!(contributor: @editor, role: "editor", display_order: 0)
      @work.work_contributors.create!(contributor: @le_guin, role: "author", display_order: 1)
      @hainish = Series.create!(name: "Hainish")
      WorkSeries.create!(work: @work, series: @hainish, position: 4)
    end

    test "lozenges, the title linked to the book, subtitle, authors first then other roles, and series" do
      render_inline(BookMastheadComponent.new(work: @work, badges: [ [ "Owned", :success ] ]))

      assert_selector "span", text: "Owned"
      assert_selector "h1 a[href='/works/#{@work.id}']", text: "The Left Hand of Darkness"
      assert_text "A Novel"
      assert_equal [ "Ursula K. Le Guin", "Brian Attebery" ], page.all("p a[href^='/authors/']").map(&:text)
      assert_text "Brian Attebery (editor)"
      assert_selector "a[href='/series/#{@hainish.id}']", text: "Hainish"
      assert_text "#4"
    end

    test "on the book's own page the title isn't a link; died: shows an author's death year" do
      render_inline(BookMastheadComponent.new(work: @work, link_title: false, died: true))

      assert_no_selector "h1 a"
      assert_text "Ursula K. Le Guin (d. 2018)"
    end
  end
end
