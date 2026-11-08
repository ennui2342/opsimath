module Ui
  # A book Mark doesn't have — from ISFDB on an author, series or line
  # page, or a wanted book with no edition yet — laid out to match
  # Ui::EditionCardComponent's `:row` / `:tile` so a page mixing the two
  # reads as one list: cover (ISFDB's, when there is one), title, author
  # line, a detail line, lozenges, and the actions passed as the block
  # (Want it / Add / Want this cover / Not this one). Dimmed unless
  # `dim: false` (a wanted book: it's in the catalogue).
  class BookCandidateCardComponent < ApplicationComponent
    include CardNumber

    def initialize(title:, authors: [], size: :row, number: nil, detail: nil, cover_url: nil, url: nil, badges: [],
                   context_author: nil, dim: true)
      raise ArgumentError, "size: #{size}" unless %i[row tile].include?(size)

      @title, @authors, @size, @number, @detail = title, Array(authors), size, number, detail
      @cover_url, @url, @badges, @context_author, @dim = cover_url, url, badges, context_author, dim
    end

    def row? = @size == :row

    def author_line
      names = @authors.compact_blank
      return if @context_author && names.map { |n| Authority.normalize(n) } == [ Authority.normalize(@context_author) ]

      EditionCardComponent.names(names).presence
    end
  end
end
