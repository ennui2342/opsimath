# An author's page asked for their bibliography: linked to ISFDB if they
# aren't yet, then their works fetched and kept (AuthorBibliography).
class AuthorBibliographyJob < ApplicationJob
  queue_as :default

  def perform(contributor_id)
    contributor = Contributor.find_by(id: contributor_id) or return
    contributor = Isfdb::ContributorLifeRefresh.link(contributor) if contributor.external_ids["isfdb"].blank? && contributor.life_checked_at.nil?
    id = contributor.external_ids["isfdb"].presence
    works = id ? Isfdb::Client.new.author_works(id) : nil
    contributor.update_columns(isfdb_works: works || [], isfdb_works_fetched_at: Time.current)
  end
end
