# An external identifier for a Work, as EditionIdentifier is for an
# Edition (docs/CATALOG.md, "Architecture review"): ISFDB's title id, Open
# Library's work key. How the add flow recognises a provider's work as one
# already catalogued.
#
# A book's ISFDB titles come from its editions' printings (docs/CATALOG.md,
# "ISFDB links from editions"); `source` says how each was learnt.
# Not unique per (id_type, value): until isfdb-adapter's 2026-11-14 fix an
# omnibus printing was credited to a novel in it, so an omnibus and the
# novel could share a title id (Peace and War / The Forever War) —
# Isfdb::LinkReconcile corrects those. "isfdb_title_rejected" records a
# link found wrong, which the lookups don't put back.
class WorkIdentifier < ApplicationRecord
  belongs_to :work

  validates :id_type, :value, presence: true
end
