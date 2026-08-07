require "test_helper"

module Ui
  class CoverComparisonComponentTest < ViewComponent::TestCase
    setup do
      @edition = Edition.create!
    end

    test "renders both covers when the current one is attached" do
      @edition.cover_image.attach(io: StringIO.new("current-bytes"), filename: "current.jpg", content_type: "image/jpeg")
      @edition.candidate_cover_image.attach(io: StringIO.new("candidate-bytes"), filename: "candidate.jpg", content_type: "image/jpeg")

      render_inline(CoverComparisonComponent.new(current: @edition.cover_image, candidate: @edition.candidate_cover_image))

      assert_text "Current"
      assert_text "Proposed"
      assert_selector "img", count: 2
    end

    test "shows a placeholder instead of an img tag when there's no current cover to compare against" do
      @edition.candidate_cover_image.attach(io: StringIO.new("candidate-bytes"), filename: "candidate.jpg", content_type: "image/jpeg")

      render_inline(CoverComparisonComponent.new(current: @edition.cover_image, candidate: @edition.candidate_cover_image))

      assert_text "No cover"
      assert_selector "img", count: 1
    end

    test "renders an 'also on file' link when another provider has a known cover URL" do
      @edition.candidate_cover_image.attach(io: StringIO.new("candidate-bytes"), filename: "candidate.jpg", content_type: "image/jpeg")

      render_inline(CoverComparisonComponent.new(
        current: @edition.cover_image, candidate: @edition.candidate_cover_image,
        other_candidates: [ { provider: "goodreads", value: "https://images.example/cover.jpg" } ]
      ))

      assert_text "Also on file: goodreads"
      assert_selector "a[href='https://images.example/cover.jpg']", text: "goodreads"
    end

    test "renders no 'also on file' line when there isn't one" do
      @edition.candidate_cover_image.attach(io: StringIO.new("candidate-bytes"), filename: "candidate.jpg", content_type: "image/jpeg")

      render_inline(CoverComparisonComponent.new(current: @edition.cover_image, candidate: @edition.candidate_cover_image))

      assert_no_text "Also on file"
    end
  end
end
