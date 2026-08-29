module Reviews
  # Reviews are stored as Markdown (see docs/DATA_MODEL.md). Goodreads is
  # the one ingestion source today and it hands back HTML — in practice
  # just prose with <br><br> paragraph breaks, occasionally an <i>/<a>
  # and stray &nbsp;. This is the one place that HTML becomes the
  # canonical Markdown; the scifipraxis path (future) already authors
  # Markdown and skips it. Rendering back to HTML for display lives in
  # Ui::MarkdownComponent.
  module Markdown
    # Goodreads uses <br> purely as a paragraph separator, never as a
    # semantic line break inside a block. Split on runs of them and wrap
    # each chunk as a real <p> so reverse_markdown emits clean
    # blank-line-separated paragraphs rather than collapsing the lot into
    # one run-on line (its text-node handler squashes bare newlines).
    BR_RUN = %r{(?:\s*<br\s*/?>\s*)+}i
    NBSP = /&nbsp;|\u00A0/i

    def self.from_html(html)
      return nil if html.blank?

      wrapped = html.gsub(NBSP, " ")
                    .split(BR_RUN).map(&:strip).reject(&:empty?)
                    .map { |para| "<p>#{para}</p>" }.join
      markdown = ReverseMarkdown.convert(wrapped, unknown_tags: :bypass, github_flavored: true)
      markdown.gsub(/[ \t]+$/, "").gsub(/\n{3,}/, "\n\n").strip
    end
  end
end
