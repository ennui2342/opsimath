require "test_helper"

class WishlistItemViewTest < ActiveSupport::TestCase
  test "a cover is new when one of its printings was announced as new lately" do
    want = create_want
    author_dead!(want)
    add_printing(want, 7, binding: "pb", publish_date: "1979", cover_group: "7")
    add_printing(want, 8, binding: "pb", publish_date: "2025", cover_group: "8")
    CatalogueEvent.create!(origin: "known_editions", kind: "new_printings", work: want.work, summary: "x",
                           details: { provider: "isfdb", provider_ids: [ "8" ] })
    CatalogueEvent.create!(origin: "known_editions", kind: "new_printings", work: want.work, summary: "old news",
                           details: { provider: "isfdb", provider_ids: [ "7" ] }, created_at: 40.days.ago)

    assert_equal [ false, true ], WishlistItemView.new(want).covers.map(&:new)
  end
end
