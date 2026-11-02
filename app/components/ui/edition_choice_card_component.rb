module Ui
  # One edition card in the add-a-book picker (docs/CATALOG.md, build step
  # 6): the edition as Mark chooses it — cover and publisher first — with
  # years, format, cover artist and which providers know it. The whole
  # card is the radio's <label>. Takes an AddBook::EditionCards::Card and
  # the signed token the radio submits; `notes` are badges over the
  # headline ("Yours now", "Same ISBN") when choosing for an edition on file.
  class EditionChoiceCardComponent < ApplicationComponent
    PROVIDER_LABELS = { "isfdb" => "ISFDB", "openlibrary" => "Open Library" }.freeze

    def initialize(card:, token:, work_title: nil, notes: [], checked: false)
      @card = card
      @token = token
      @work_title = work_title
      @notes = notes
      @checked = checked
    end

    attr_reader :card, :token, :notes, :checked

    def headline = [ card.publisher.presence || "Publisher unknown", card.years.first(3).join(", ").presence ].compact.join(" · ")

    def detail = [ card.format_label, card.cover_artist ].compact.join(" · ")

    def sources = card.providers.map { |p| PROVIDER_LABELS.fetch(p, p) }.join(" + ")

    # An omnibus or retitled printing shows its own title.
    def own_title
      title = card.primary.title
      title if title.present? && @work_title && fold(title) != fold(@work_title)
    end

    private

    def fold(text) = text.to_s.downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
