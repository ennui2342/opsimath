# An author's page: their books in the catalogue, in publication order,
# with where each stands for Mark — and any other roles (editor,
# translator) apart. Linked from the book page.
class AuthorsController < ApplicationController
  def show
    @author = Contributor.find(params[:id])
    roles = @author.work_contributors.includes(work: WorksController::LIST_INCLUDES).to_a
    @by_role = roles.group_by(&:role).transform_values do |wcs|
      wcs.map(&:work).uniq.sort_by { |w| [ w.original_publication_year || 9999, w.title.to_s.downcase ] }
    end
  end
end
