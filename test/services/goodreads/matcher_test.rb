require "test_helper"

module Goodreads
  class MatcherTest < ActiveSupport::TestCase
    def item(goodreads_book_id:, title:, author_name:, isbn: nil)
      RssClient::FeedItem.new(goodreads_book_id: goodreads_book_id, title: title, author_name: author_name, isbn: isbn)
    end

    test "tier 1: matches an existing catalog Edition by goodreads_book_id" do
      work = Work.create!(title: "Neuromancer", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "goodreads", value: "953070")

      result = Matcher.match(item(goodreads_book_id: "953070", title: "Neuromancer", author_name: "William Gibson"))

      assert_equal work, result.work
      assert_equal edition, result.edition
      assert_not result.ambiguous
    end

    test "tier 2: falls back to isbn10 when goodreads_book_id isn't known" do
      work = Work.create!(title: "Europe at Dawn", literary_form: "novel")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      EditionIdentifier.create!(edition: edition, id_type: "isbn10", value: "1781086095")

      result = Matcher.match(item(goodreads_book_id: "39666185", title: "Europe at Dawn", author_name: "Dave Hutchinson", isbn: "1781086095"))

      assert_equal work, result.work
      assert_equal edition, result.edition
    end

    test "tier 3: exact normalized title+author matches the work but NOT a specific edition" do
      work = Work.create!(title: "Existentialism from Dostoevsky to Sartre", literary_form: "nonfiction")
      edition = Edition.create!
      EditionContent.create!(work: work, edition: edition)
      contributor = Contributor.create!(name: "Walter Kaufmann")
      WorkContributor.create!(work: work, contributor: contributor, role: "author")

      result = Matcher.match(item(goodreads_book_id: "999999", title: "Existentialism from Dostoevsky to Sartre", author_name: "Walter Kaufmann"))

      assert_equal work, result.work
      assert_nil result.edition, "a work-only match leaves the edition for EditionReconciliation to resolve"
      assert_not result.ambiguous
    end

    test "returns nil (safe to auto-create) when nothing matches at all" do
      result = Matcher.match(item(goodreads_book_id: "0", title: "Some Book Nobody Owns", author_name: "Nobody Real"))

      assert_nil result
    end

    test "flags ambiguous when title+author matches more than one Work" do
      contributor = Contributor.create!(name: "Ambiguous Author")
      2.times { |i| Work.create!(title: "Duplicate Title", literary_form: "novel").tap { |w| WorkContributor.create!(work: w, contributor: contributor, role: "author") } }

      result = Matcher.match(item(goodreads_book_id: "0", title: "Duplicate Title", author_name: "Ambiguous Author"))

      assert result.ambiguous
      assert_nil result.work
    end
  end
end
