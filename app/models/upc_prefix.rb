# A US mass-market UPC publisher code (UPC digits 2-6) and the ISBN
# prefixes it stands for — several for some (Tor: 0812 and 0765). Seeded
# from LibraryThing's table, then learnt by UpcLookup: a scan's candidates
# narrow `candidates` until one is left, which joins `known_prefixes`.
class UpcPrefix < ApplicationRecord
  validates :manufacturer, presence: true, uniqueness: true, format: { with: /\A\d{5}\z/ }
end
