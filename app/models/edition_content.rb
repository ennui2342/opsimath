class EditionContent < ApplicationRecord
  belongs_to :edition
  belongs_to :work
end
