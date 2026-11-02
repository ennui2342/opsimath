# Free-text publication dates -> EDTF strings ("1978", "1978-04",
# "1978-04-15"), keeping only the precision the text actually gives — the
# same rule as Edition#publish_date (docs/DATA_MODEL.md): a year-only date
# never gains an invented month. For providers that send prose dates
# ("April 1996", "Sep 16, 1990", "cop. 2021"); Open Library does.
module Edtf
  module_function

  MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  # -> EDTF string, or nil when the text holds no plausible year.
  def from_text(text)
    s = text.to_s.strip
    return s if s.match?(/\A\d{4}(-\d{2}(-\d{2})?)?\z/) # already EDTF

    year = s[/\b(1[4-9]\d\d|20\d\d)\b/, 1] or return nil
    month_index = MONTHS.index(s.downcase[/\b(#{MONTHS.join('|')})[a-z]*\.?\b/, 1])
    return year unless month_index

    month = format("%02d", month_index + 1)
    day = s[/\b(?:#{MONTHS.join('|')})[a-z]*\.?\s+(\d{1,2})\b/i, 1] || s[/\b(\d{1,2})\s+(?:#{MONTHS.join('|')})/i, 1]
    day && day.to_i.between?(1, 31) ? "#{year}-#{month}-#{format('%02d', day.to_i)}" : "#{year}-#{month}"
  end
end
