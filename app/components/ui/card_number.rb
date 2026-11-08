module Ui
  # A book card's `number:` on a row, on the title line rather than in a
  # column of its own (Mark, 2026-11-08): a series number before the title
  # ("#3 Title"), a year after it, dot-separated ("Title · 1980").
  module CardNumber
    def number_prefix
      return unless @number.to_s.start_with?("#")

      helpers.tag.span("#{@number} ", data: { card_number: true }, class: "text-sm tabular-nums text-gray-500 dark:text-gray-400")
    end

    def number_suffix
      return if @number.blank? || @number.to_s.start_with?("#")

      helpers.tag.span(" · #{@number}", data: { card_number: @number.to_s }, class: "text-sm tabular-nums text-gray-500 dark:text-gray-400")
    end
  end
end
