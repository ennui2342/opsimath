module Ui
  # The heading of any page about one book (docs/DESIGN_SYSTEM.md, "Book
  # masthead") — the book page, bargain hunting, the pending-decision
  # screens, choosing a printing, an eBay listing — laid out once so it can
  # change in one place (Mark, 2026-11-09): lozenges above, the title
  # (linked to the book's page, except on that page), its subtitle, the
  # authors and other contributors linked to their pages, and its series
  # with numbers. Lozenges come as `badges:` ([text, variant] pairs); the
  # block, if any, adds lines beneath.
  class BookMastheadComponent < ApplicationComponent
    def initialize(work:, badges: [], link_title: true, died: false, size: :page)
      @work = work
      @badges = badges
      @link_title = link_title
      @died = died
      @size = size
    end

    def title_class = @size == :page ? "text-3xl font-bold text-gray-900 dark:text-gray-100" : "text-2xl font-bold text-gray-900 dark:text-gray-100"

    def title_html
      @link_title ? helpers.work_link(@work) : @work.title
    end

    # Authors first, then other roles ("Ann (editor)"), each linked; an
    # author's death year with `died:` (bargain hunting's buy-new rule).
    # Plain contributors — an anthology's, an introduction's — folded away
    # behind "and 22 contributors".
    def contributors_html
      wcs = @work.work_contributors.sort_by { |wc| [ wc.role == "author" ? 0 : 1, wc.display_order || Float::INFINITY ] }
      named, others = wcs.partition { |wc| wc.role != "contributor" }
      credits = helpers.safe_join(named.map do |wc|
        link = person_link(wc)
        died = (" (d. #{wc.contributor.died_date.first(4)})" if @died && wc.role == "author" && wc.contributor.died_date)
        role = (" (#{wc.role})" unless wc.role == "author")
        helpers.safe_join([ link, died, role ].compact)
      end, ", ")
      return credits if others.empty?

      folded = helpers.tag.details(class: "inline [&[open]>summary]:hidden") do
        helpers.tag.summary("#{'and ' if named.any?}#{helpers.pluralize(others.size, 'contributor')}", class: "inline cursor-pointer hover:underline") +
          helpers.safe_join(others.map { |wc| person_link(wc) }, ", ")
      end
      helpers.safe_join([ credits, folded ].compact_blank, " ")
    end

    def person_link(wc) = helpers.link_to(wc.contributor.name, helpers.author_path(wc.contributor), class: "hover:underline")

    def series_html
      return if @work.work_series.empty?

      helpers.safe_join(@work.work_series.map do |ws|
        helpers.safe_join([ helpers.link_to(ws.series.name, helpers.series_path(ws.series), class: "hover:underline"),
                            (" ##{format('%g', ws.position)}" if ws.position) ].compact)
      end, ", ")
    end
  end
end
