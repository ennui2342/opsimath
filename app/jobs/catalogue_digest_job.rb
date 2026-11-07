# Each morning, after the nightly jobs: what they changed in the catalogue,
# to Discord's #catalogue (CatalogueReport).
class CatalogueDigestJob < ApplicationJob
  queue_as :default

  def perform = CatalogueReport.post_digest
end
