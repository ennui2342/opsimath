# An external identifier for a Work, as EditionIdentifier is for an
# Edition (docs/CATALOG.md, "Architecture review"): ISFDB's title id, Open
# Library's work key. How the add flow recognises a provider's work as one
# already catalogued.
#
# Not unique per (id_type, value): ISFDB resolves an omnibus edition's ISBN
# to a novel inside it, so the omnibus and the novel can share a title id
# (Peace and War / The Forever War). `source` says how it was learnt.
class WorkIdentifier < ApplicationRecord
  belongs_to :work

  validates :id_type, :value, presence: true
end
