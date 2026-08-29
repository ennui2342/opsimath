# Reviews are now stored as Markdown (docs/DATA_MODEL.md). Every review
# on file arrived from Goodreads as HTML (prose + <br><br>, the odd
# &nbsp;); convert each in place through the same Reviews::Markdown.from_html
# the ingestion paths now use. update! (not update_columns) so PaperTrail
# keeps the pre-conversion HTML as a recoverable version. Irreversible —
# the conversion is one-way and the original is in the audit trail.
class ConvertExistingReviewsToMarkdown < ActiveRecord::Migration[8.1]
  def up
    Review.reset_column_information
    Review.find_each do |review|
      markdown = Reviews::Markdown.from_html(review.text)
      review.update!(text: markdown) if markdown.present? && markdown != review.text
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
