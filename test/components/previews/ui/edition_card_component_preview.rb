module Ui
  class EditionCardComponentPreview < ViewComponent::Preview
    PNG_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")

    # A fully-populated printing: cover, format_detail, publisher + year +
    # pages, and a linked ISFDB / Goodreads id alongside the plain ISBNs.
    def full
      edition = Edition.create!(format: "paperback", format_detail: "mass_market", publisher: "Grafton", publish_date: "1988", page_count: 471)
      edition.cover_image.attach(io: StringIO.new(PNG_BYTES), filename: "cover.png", content_type: "image/png")
      EditionIdentifier.create!(edition:, id_type: "isbn13", value: "9780586213872")
      EditionIdentifier.create!(edition:, id_type: "isbn10", value: "0586213872")
      EditionIdentifier.create!(edition:, id_type: "isfdb", value: "12345")
      EditionIdentifier.create!(edition:, id_type: "goodreads", value: "1343099")
      render(EditionCardComponent.new(edition:))
    end

    # The sparse case Goodreads' RSS often produces — no cover, no format,
    # one ISBN.
    def sparse
      edition = Edition.create!(publisher: "Tor")
      EditionIdentifier.create!(edition:, id_type: "isbn10", value: "0812501810")
      render(EditionCardComponent.new(edition:))
    end
  end
end
