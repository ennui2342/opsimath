# Reading lists (docs/LISTS.md): every list with Mark's progress through
# it, adding an award list from ISFDB, and a list's page — every book on
# it and where each stands for him, "Want it", and collecting the list.
class BookListsController < ApplicationController
  before_action :set_list, except: %i[index create]

  def index
    @lists = BookList.order(:kind, :name).to_a
    @views = @lists.to_h { |l| [ l.id, BookListView.for(l) ] }
    @awards = award_types if params[:add]
    @award = @awards&.find { |a| a["id"] == params[:award].to_s }
  end

  # Add an award list: one category of one award, from ISFDB.
  def create
    list = BookLists::Import.new.award(Integer(params[:category_id]))
    return redirect_to(book_lists_path, alert: "ISFDB has no such award category.") unless list

    CatalogueEvent.record(kind: "list_added", summary: "Added the list #{list.name}")
    redirect_to book_list_path(list)
  end

  def show
    @list_want = @list.book_list_want
    @scope = params[:scope].presence_in(BookListWant::SCOPES) || "shortlist"
    @from_year = params[:from].presence&.to_i
    @view = BookListView.for(@list, scope: @scope, from_year: @from_year)
  end

  def want_entry
    entry = BookListView.for(@list).entries.find { |e| e.isfdb_title_id == Integer(params[:title_id]) }
    return redirect_to(book_list_path(@list), alert: "That book isn't on this list.") unless entry

    BookListWants::Sync.want_entry(@list, entry)
    redirect_back_or_to book_list_path(@list), notice: "“#{entry.title}” is on your wishlist."
  end

  def collect
    list_want = BookListWant.find_or_initialize_by(book_list: @list)
    list_want.update!(scope: params[:scope].presence_in(BookListWant::SCOPES) || "winners", from_year: params[:from_year].presence&.to_i)
    added = BookListWants::Sync.run(list_want)
    CatalogueEvent.record(kind: "list_collecting", summary: "Collecting #{@list.name} (#{list_want.scope}#{", from #{list_want.from_year}" if list_want.from_year})")
    redirect_to book_list_path(@list), notice: "Collecting this list — #{helpers.pluralize(added, 'book')} added to your wishlist, and any that join it later."
  end

  def stop
    @list.book_list_want&.stop!
    redirect_to book_list_path(@list), notice: "Stopped collecting this list; the wants it added are gone."
  end

  # "Not this one": the book stays out, and a want the list made for it goes.
  def exclude
    list_want = @list.book_list_want or return redirect_to(book_list_path(@list))
    title_id = Integer(params[:title_id])
    list_want.update!(excluded_title_ids: list_want.excluded_title_ids | [ title_id ])
    list_want.wants.select { |w| w.work.work_identifiers.any? { |i| i.id_type == "isfdb_title" && i.value == title_id.to_s } }.each(&:retire!)
    redirect_back_or_to book_list_path(@list)
  end

  def include
    list_want = @list.book_list_want or return redirect_to(book_list_path(@list))
    list_want.update!(excluded_title_ids: list_want.excluded_title_ids - [ Integer(params[:title_id]) ])
    BookListWants::Sync.run(list_want)
    redirect_back_or_to book_list_path(@list)
  end

  LATIN = /\A[\p{Latin}\p{Common}\p{Inherited}]+\z/

  def self.latin_name(award)
    names = [ award["name"], award["short_name"] ].map { |n| CGI.unescapeHTML(n.to_s) }
    parts = names.flat_map { |n| [ n, *n.split(" / ") ] }.map(&:strip).compact_blank
    parts.find { |n| n.match?(LATIN) } || names.first
  end

  private

  def set_list
    @list = BookList.find(params[:id])
  end

  # ISFDB's awards with categories that have entries, cached a day, by
  # name — in Latin script: ISFDB keeps a Russian or Japanese award's name
  # as HTML character references, with the transliteration after a slash
  # ("Аэлита / Aelita").
  def award_types
    Rails.cache.fetch("isfdb/awards", expires_in: 1.day, skip_nil: true) { Isfdb::Client.new.award_types }
                .map { |a| a.merge("name" => self.class.latin_name(a), "categories" => Array(a["categories"]).select { |c| c["entries"].to_i.positive? }) }
                .select { |a| a["categories"].any? }
                .sort_by { |a| I18n.transliterate(a["name"]).downcase.sub(/\Athe /, "") }
  rescue Isfdb::ServiceError, Net::OpenTimeout, Net::ReadTimeout => e
    Rails.logger.warn("awards: #{e.class}: #{e.message}")
    []
  end
end
