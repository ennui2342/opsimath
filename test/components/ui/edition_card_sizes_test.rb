require "test_helper"

module Ui
  class EditionCardSizesTest < ViewComponent::TestCase
    setup do
      @king = Contributor.create!(name: "Stephen King")
      @work = Work.create!(title: "The Long Walk", literary_form: "novel")
      @work.work_contributors.create!(contributor: @king, role: "author")
      @edition = Edition.create!(publisher: "Signet", publish_date: "1979", format: "paperback", cover_artist: "Uncredited")
      EditionContent.create!(work: @work, edition: @edition)
      Copy.create!(edition: @edition, disposition: "owned")
    end

    test "a row: cover, title, author, publisher · year, lozenges — no identifiers or cog" do
      render_inline(EditionCardComponent.new(edition: @edition, size: :row, number: "1979"))

      assert_selector "[data-card=edition] [data-card-title]", text: "The Long Walk"
      assert_text "Stephen King"
      assert_text "Signet · 1979 · Paperback · Uncredited"
      assert_selector "span", text: "Owned"
      assert_no_selector "a[aria-label='Reconcile this edition\\'s metadata']"
    end

    test "the author line names a pseudonymous credit with the real author, and drops the page's own author" do
      @edition.edition_identifiers.create!(id_type: "isfdb", value: "77")
      @work.provider_editions.create!(provider: "isfdb", provider_id: "77", author_names: [ "Richard Bachman" ], author_ids: [ 9 ])
      work = Work.includes(:provider_editions, work_contributors: :contributor).find(@work.id)

      render_inline(EditionCardComponent.new(edition: @edition, size: :row, work:, context_author: "Stephen King"))
      assert_text "Richard Bachman (Stephen King)"

      @work.provider_editions.update_all(author_names: [ "Stephen King" ])
      work = Work.includes(:provider_editions, work_contributors: :contributor).find(@work.id)
      render_inline(EditionCardComponent.new(edition: @edition, size: :row, work:, context_author: "Stephen King"))
      assert_no_text "Stephen King"
    end

    test "a book not in the catalogue: dimmed, its actions from the block" do
      render_inline(BookCandidateCardComponent.new(title: "Rage", authors: [ "Stephen King" ], number: "1977")) { "Want it" }

      assert_selector "[data-card=candidate] [data-card-title]", text: "Rage"
      assert_selector ".opacity-60"
      assert_text "Want it"
    end
  end
end
