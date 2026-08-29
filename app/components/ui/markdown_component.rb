module Ui
  # Renders stored Markdown (a Review's text today, private notes later)
  # to sanitized HTML for display. kramdown is Jekyll's parser too, so a
  # review renders here the same way it will when published to
  # scifipraxis. See docs/UI_PRINCIPLES.md principle 5 (ViewComponent)
  # and docs/DATA_MODEL.md (Review.text is Markdown).
  class MarkdownComponent < ApplicationComponent
    # Reviews are self-authored prose — no need for the full HTML surface.
    ALLOWED_TAGS = %w[p br em strong a ul ol li blockquote h1 h2 h3 h4 h5 h6 code pre hr].freeze
    ALLOWED_ATTRIBUTES = %w[href].freeze

    def initialize(text:)
      @text = text.to_s
    end

    def render?
      @text.present?
    end

    def call
      rendered = Kramdown::Document.new(@text, auto_ids: false, input: "GFM").to_html
      tag.div(sanitize(rendered, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES), class: "markdown")
    end
  end
end
