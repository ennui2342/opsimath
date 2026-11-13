require "test_helper"

class BookListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @list = BookList.create!(key: "pringle_100", name: "Pringle's 100", short_name: "Pringle 100", kind: "curated")
    @list.entries.create!(title: "Earth Abides", author: "George R. Stewart", year: 1949, position: 2, status: "listed", isfdb_title_id: 50)
    @list.entries.create!(title: "Limbo", author: "Bernard Wolfe", year: 1952, position: 6, status: "listed")
  end

  test "the lists page and a list's page: progress, and Want it for a matched book" do
    get book_lists_url
    assert_select "[data-book-list]", text: /read 0 of 2/

    get book_list_url(@list)
    assert_select "[data-progress]", text: /read 0 of 2 · own 0/
    assert_select "[data-entry]", 2
    assert_select "form[action='#{want_entry_book_list_path(@list)}']", 1 # Limbo isn't on ISFDB: no Want it
  end

  test "Want it adds the book and wants it; the book page then shows the list" do
    post want_entry_book_list_url(@list), params: { title_id: 50 }

    work = Work.find_by!(title: "Earth Abides")
    assert work.want
    get work_url(work)
    assert_select "[data-list-badge]", text: "Pringle 100 #2"
  end

  test "collecting and stopping" do
    post collect_book_list_url(@list), params: { scope: "winners" }
    assert_equal 1, Want.count

    delete collect_book_list_url(@list)
    assert_equal 0, Want.count
    assert_nil @list.reload.book_list_want
  end
end
