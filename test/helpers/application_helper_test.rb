require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "work_link links a book's title to its page; work_links joins several, or falls back" do
    work = Work.create!(title: "Contact", literary_form: "novel")

    assert_dom_equal %(<a class="hover:underline font-medium" href="/works/#{work.id}">Contact</a>), work_link(work, classes: "font-medium")
    assert_equal "Edition #9", work_links([], fallback: "Edition #9")
  end
end
