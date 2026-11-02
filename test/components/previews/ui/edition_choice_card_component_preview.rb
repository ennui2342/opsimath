module Ui
  class EditionChoiceCardComponentPreview < ViewComponent::Preview
    def isfdb_and_open_library
      card = AddBook::EditionCards::Card.new(editions: [
        Providers::Edition.new(provider: "isfdb", id: "2", publisher: "Orbit", publish_date: "1979", binding: "pb",
                               cover_artist: "Peter Jones", isbn10: "0860079422",
                               cover_url: "https://www.isfdb.org/wiki/images/2/2b/BRTHGRVRB1979.jpg"),
        Providers::Edition.new(provider: "openlibrary", id: "OL1M", publisher: "Futura")
      ])
      render(EditionChoiceCardComponent.new(card:, token: "preview", work_title: "The Birthgrave"))
    end

    def no_cover_omnibus
      card = AddBook::EditionCards::Card.new(editions: [ Providers::Edition.new(provider: "isfdb", id: "9", publisher: "Gollancz",
                                                                                title: "Peace and War", binding: "tp", publish_date: "2006") ])
      render(EditionChoiceCardComponent.new(card:, token: "preview", work_title: "The Forever War"))
    end
  end
end
