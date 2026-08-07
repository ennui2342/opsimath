module Ui
  class CoverComparisonComponentPreview < ViewComponent::Preview
    # A minimal valid 1x1 PNG — real bytes, so the variant this component
    # renders can genuinely be processed and displayed in the browser
    # preview, not just link to a broken image.
    PNG_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    def default
      edition = Edition.create!
      edition.cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "current.png", content_type: "image/png")
      edition.candidate_cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "candidate.png", content_type: "image/png")

      render(CoverComparisonComponent.new(current: edition.cover_image, candidate: edition.candidate_cover_image))
    end

    def no_current_cover
      edition = Edition.create!
      edition.candidate_cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "candidate.png", content_type: "image/png")

      render(CoverComparisonComponent.new(current: edition.cover_image, candidate: edition.candidate_cover_image))
    end
  end
end
