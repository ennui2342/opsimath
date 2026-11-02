# Building wanted books for tests (docs/CATALOG.md): a Want on a new Work
# with its author, ISFDB printings as the work's provider editions, and the
# author's ISFDB life status.
module WishlistTestHelper
  def create_want(title: "The Birthgrave", author: "Tanith Lee", isbns: [], external_ids: {}, cover_url: nil, **attrs)
    want = Want.add!(title:, author_name: author, isbns:, external_ids:, cover_url:)
    want.update!(attrs) if attrs.any?
    want
  end

  # An ISFDB printing of the want's work (a ProviderEdition, pub id as its id).
  def add_printing(want, pub_id, binding: "pb", **attrs)
    want.work.provider_editions.create!(provider: "isfdb", provider_id: pub_id.to_s, binding:, **attrs)
  end

  def author_dead!(want, died_date = "2015-05-24")
    want.author.update!(external_ids: { "isfdb" => "1" }, died_date:, life_checked_at: Time.current)
  end

  def author_living!(want)
    want.author.update!(external_ids: { "isfdb" => "1" }, died_date: nil, life_checked_at: Time.current)
  end
end
