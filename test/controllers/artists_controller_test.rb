require "test_helper"

class ArtistsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @mine = Work.create!(title: "Pacific Edge", literary_form: "novel")
    edition = Edition.create!(publisher: "HarperCollins (UK)", publish_date: "1995", cover_artist: "Peter Elson")
    EditionContent.create!(work: @mine, edition:)
    Copy.create!(edition:, disposition: "owned")
    shared = Work.create!(title: "Joint Cover", literary_form: "novel")
    EditionContent.create!(work: shared, edition: Edition.create!(cover_artist: "Chris Foss, Peter Elson"))
    @want = create_want(title: "Jizzle")
    author_dead!(@want)
    add_printing(@want, 9, binding: "pb", publish_date: "1977", publisher: "Panther", cover_artist: "Peter Elson", cover_url: "https://covers.test/9.jpg")
  end

  test "an artist's covers in the catalogue, shared credits included, and on the wishlist" do
    get artist_url(name: "Peter Elson")

    assert_select "h1", /Peter Elson/
    assert_select "a[href=?]", work_path(@mine), text: /Pacific Edge/
    assert_select "span", text: "Joint Cover"
    assert_select "a[href=?]", wishlist_item_path(@want), text: /Jizzle/
  end

  test "the book page links an edition's cover artist" do
    get work_url(@mine)

    assert_select "a[href=?]", artist_path(name: "Peter Elson"), text: "Peter Elson"
  end
end
