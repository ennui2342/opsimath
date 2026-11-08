# A US mass-market UPC publisher code and the ISBN prefix it stands for,
# learnt by UpcLookup (no published table exists). `prefix` is set once a
# scan leaves only one of the `candidates`.
class UpcPrefix < ApplicationRecord
  validates :manufacturer, presence: true, uniqueness: true, format: { with: /\A\d{5}\z/ }
end
