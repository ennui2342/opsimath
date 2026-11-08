# An author's page: every book of theirs — the catalogue's and, once
# linked to ISFDB, their whole bibliography (AuthorBibliography) — grouped
# by kind, with where each stands for Mark and a "Want it" for one he
# doesn't have; other roles (editor, translator) apart. Linked from the
# book page.
class AuthorsController < ApplicationController
  def show
    @author = Contributor.find(params[:id])
    roles = @author.work_contributors.includes(work: WorksController::CARD_INCLUDES).to_a
    @other_roles = roles.reject { |wc| wc.role == "author" }.group_by(&:role).transform_values do |wcs|
      wcs.map(&:work).uniq.sort_by { |w| [ w.original_publication_year || 9999, w.title.to_s.downcase ] }
    end
    @bibliography = AuthorBibliography.for(@author)
    AuthorBibliographyJob.perform_later(@author.id) if @bibliography.stale?
  end

  # "Want it": a book of theirs from ISFDB, into the catalogue and wanted.
  def want_title
    author = Contributor.find(params[:id])
    entry = AuthorBibliography.for(author).entries.find { |e| e.title_id == Integer(params[:title_id]) }
    return redirect_to(author_path(author), alert: "That book isn't in their ISFDB bibliography.") unless entry

    work = entry.work || AddBook::Create.create_work("title" => entry.title, "authors" => [ author.name ], "first_year" => entry.year,
                                                     "provider_works" => [ { "provider" => "isfdb", "id" => entry.title_id.to_s } ])
    unless work.want
      WantPrintingsJob.perform_later(work.create_want!.id)
      CatalogueEvent.record(kind: "wanted", work:, summary: "Wanted #{work.title}")
    end
    redirect_to author_path(author), notice: "“#{work.title}” is on your wishlist."
  end
end
