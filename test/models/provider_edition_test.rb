require "test_helper"

class ProviderEditionTest < ActiveSupport::TestCase
  test "isbns_by_work gives each work's ISBN-13s once, ISBN-10s folded, in a stable order" do
    work = Work.create!(title: "Crossfire", literary_form: "novel")
    other = Work.create!(title: "Other", literary_form: "novel")
    work.provider_editions.create!(provider: "isfdb", provider_id: "1", isbn13: "9780765304674")
    work.provider_editions.create!(provider: "isfdb", provider_id: "2", isbn10: "0812564022")
    work.provider_editions.create!(provider: "openlibrary", provider_id: "OL1M", isbn13: "9780765304674") # same book, another provider
    work.provider_editions.create!(provider: "isfdb", provider_id: "3") # no ISBN
    other.provider_editions.create!(provider: "isfdb", provider_id: "9", isbn13: "9780000000002")

    result = ProviderEdition.isbns_by_work([ work.id ])

    assert_equal({ work.id => [ "9780765304674", Isbn.to_13("0812564022") ] }, result)
  end
end
