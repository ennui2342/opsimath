# ISBN-10 <-> ISBN-13 conversion and check-digit validation. Pure, no
# database. The shop-lookup PWA (docs/MOBILE.md) matches barcode scans
# (EAN-13 = ISBN-13) against stored identifiers, so every edition that
# has one form should carry the other where it's derivable — and the
# derivation is deterministic, not a lookup.
module Isbn
  module_function

  # Digits only, uppercased trailing X, or nil if it's not a plausible
  # ISBN-10/13 to begin with.
  def normalize(raw)
    s = raw.to_s.gsub(/[\s-]/, "").upcase
    return s if s.match?(/\A\d{9}[\dX]\z/) || s.match?(/\A\d{13}\z/)

    nil
  end

  def valid_10?(raw)
    s = normalize(raw)
    s&.length == 10 && s[9] == isbn10_check_digit(s[0, 9])
  end

  def valid_13?(raw)
    s = normalize(raw)
    s&.length == 13 && s[12] == isbn13_check_digit(s[0, 12])
  end

  # ISBN-10 -> ISBN-13 (978 prefix). nil for anything that isn't a valid
  # ISBN-10.
  def to_13(raw)
    s = normalize(raw)
    return nil unless s&.length == 10 && valid_10?(s)

    body = "978#{s[0, 9]}"
    "#{body}#{isbn13_check_digit(body)}"
  end

  # ISBN-13 -> ISBN-10, only for the 978 prefix (979- has no ISBN-10
  # equivalent). nil otherwise.
  def to_10(raw)
    s = normalize(raw)
    return nil unless s&.length == 13 && valid_13?(s) && s.start_with?("978")

    body = s[3, 9]
    "#{body}#{isbn10_check_digit(body)}"
  end

  # The check character for a 9-digit ISBN-10 body: "0"-"9" or "X".
  def isbn10_check_digit(body9)
    remainder = 11 - body9.chars.each_with_index.sum { |c, i| c.to_i * (10 - i) } % 11
    { 10 => "X", 11 => "0" }.fetch(remainder, remainder.to_s)
  end
  private_class_method :isbn10_check_digit

  # The check digit for a 12-digit ISBN-13 body, as a "0"-"9" string.
  def isbn13_check_digit(body12)
    sum = body12.chars.each_with_index.sum { |c, i| c.to_i * (i.even? ? 1 : 3) }
    ((10 - sum % 10) % 10).to_s
  end
  private_class_method :isbn13_check_digit

  # English-group ISBN-10 publisher ranges: [group digit, low, high, code
  # length] — a publisher's code length is fixed by its range.
  ENGLISH_PUBLISHER_RANGES = [ [ "0", 0, 19, 2 ], [ "0", 200, 699, 3 ], [ "0", 7000, 8499, 4 ], [ "0", 85_000, 89_999, 5 ],
                               [ "0", 900_000, 949_999, 6 ], [ "1", 0, 9, 2 ], [ "1", 100, 399, 3 ], [ "1", 4000, 5499, 4 ],
                               [ "1", 55_000, 86_979, 5 ] ].freeze

  # The group + publisher part of an English-group ISBN-10 ("088677" for
  # 0-88677-299-0, "08125" for Tor's 0-8125-5010-2), or nil.
  def publisher_prefix(isbn10)
    first9 = isbn10.to_s[0, 9]
    return unless first9.match?(/\A[01]\d{8}\z/)

    ENGLISH_PUBLISHER_RANGES.each do |group, low, high, length|
      next unless first9.start_with?(group)

      code = first9[1, length].to_i
      return first9[0, 1 + length] if code.between?(low, high)
    end
    nil
  end
end
