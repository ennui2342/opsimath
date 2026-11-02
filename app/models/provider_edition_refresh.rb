# When a provider's editions for a work were last fetched, and from which
# of the work's ISBNs — so KnownEditionsRefresh re-queries a work only when
# it's due or its ISBNs changed. One row per (work, provider).
class ProviderEditionRefresh < ApplicationRecord
  belongs_to :work
end
