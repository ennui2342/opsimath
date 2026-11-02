require "test_helper"

# The book page's catalogue actions (docs/CATALOG.md, build step 5):
# the reading log, copies, and wishlist membership.
class CatalogueActionsTest < ActionDispatch::IntegrationTest
  setup do
    @work = Work.create!(title: "Neuromancer", literary_form: "novel")
    @edition = Edition.create!(format: "paperback", publisher: "Ace Books", publish_date: "1984")
    EditionContent.create!(work: @work, edition: @edition)
    @copy = Copy.create!(edition: @edition, disposition: "owned")
    sign_in_as users(:one)
  end

  test "start reading, then finish with a rating and a draft review" do
    post work_readings_url(@work), params: { reading: { edition_id: @edition.id, date_started: "2026-11-01", source: "owned_copy" } }
    reading = @work.readings.sole
    assert_equal [ "reading", Date.new(2026, 11, 1) ], [ reading.status, reading.date_started ]

    patch work_reading_url(@work, reading), params: { reading: { status: "completed", date_finished: "2026-11-03", rating: "4" },
                                                      review: { text: "Still **sharp**." } }

    assert_redirected_to work_path(@work)
    assert_equal "Finished.", flash[:notice]
    reading.reload
    assert_equal [ "completed", Date.new(2026, 11, 3), 4 ], [ reading.status, reading.date_finished, reading.rating.to_i ]
    review = @work.reviews.sole
    assert_equal [ "Still **sharp**.", "draft", reading, 4 ], [ review.text, review.status, review.reading, review.rating.to_i ]
  end

  test "did not finish, with a reason; pause and resume" do
    reading = @work.readings.create!(edition: @edition, status: "reading", date_started: Date.new(2026, 10, 1))

    patch work_reading_url(@work, reading), params: { reading: { status: "paused" } }
    assert_equal "paused", reading.reload.status
    assert_equal "Paused.", flash[:notice]
    patch work_reading_url(@work, reading), params: { reading: { status: "reading" } }
    assert_equal "reading", reading.reload.status

    patch work_reading_url(@work, reading), params: { reading: { status: "dnf", dnf_reason: "Not now" } }
    reading.reload
    assert_equal [ "dnf", "Not now", Date.current ], [ reading.status, reading.dnf_reason, reading.date_finished ]
  end

  test "a finish date before the start is refused, with the reason" do
    reading = @work.readings.create!(edition: @edition, status: "reading", date_started: Date.new(2026, 10, 1))

    patch work_reading_url(@work, reading), params: { reading: { status: "completed", date_finished: "2026-09-01" } }

    assert_equal "reading", reading.reload.status
    assert_match(/before the start date/, flash[:alert])
  end

  test "a past reading can be corrected, or deleted — its review stays" do
    reading = @work.readings.create!(edition: @edition, status: "completed", date_finished: Date.new(2020, 1, 1), rating: 3)
    review = Review.create!(work: @work, reading:, text: "Hm.", status: "published")

    patch work_reading_url(@work, reading), params: { reading: { rating: "5", date_finished: "2021-02-02" } }
    assert_equal [ 5, Date.new(2021, 2, 2) ], [ reading.reload.rating.to_i, reading.date_finished ]
    assert_equal 2, reading.versions.count # created + corrected: full history now

    delete work_reading_url(@work, reading)
    assert_not Reading.exists?(reading.id)
    assert_nil review.reload.reading_id
  end

  test "add a copy; record what became of one" do
    post work_copies_url(@work), params: { copy: { edition_id: @edition.id, acquired_date: "2026-11-02", acquired_price: "4.50",
                                                   acquired_source: "eBay", condition: "Good" } }
    added = @edition.copies.order(:id).last
    assert_equal [ "owned", BigDecimal("4.50"), "eBay" ], [ added.disposition, added.acquired_price, added.acquired_source ]

    patch work_copy_url(@work, @copy), params: { copy: { disposition: "sold" } }
    assert_equal "sold", @copy.reload.disposition
  end

  test "an unknown disposition is ignored, not an error" do
    patch work_copy_url(@work, @copy), params: { copy: { disposition: "stolen" } }

    assert_redirected_to work_path(@work)
    assert_equal "owned", @copy.reload.disposition
  end

  test "add a book you own to the wishlist, and remove it — the book stays" do
    post work_want_url(@work)
    assert @work.reload.want

    delete work_want_url(@work)
    assert_nil @work.reload.want
    assert Work.exists?(@work.id)
  end

  test "removing a wanted-only book takes its empty placeholder work with it" do
    want = create_want(title: "Vagabonds", author: "Hao Jingfang")
    work = want.work

    delete work_want_url(work)

    assert_redirected_to works_path
    assert_not Work.exists?(work.id)
  end

  test "the Books list shows where each book stands, and filters by it" do
    create_want(title: "Vagabonds", author: "Hao Jingfang")
    @work.readings.create!(edition: @edition, status: "completed")

    get works_url
    assert_response :success
    assert_select "a[href=?]", works_path(filter: "wanted"), text: "Wanted (1)"
    assert_select "span", text: "Read"

    get works_url(filter: "wanted")
    assert_select "a", text: /Vagabonds/
    assert_select "a", text: /Neuromancer/, count: 0
  end

  test "the book page offers starting a read, copies, and the wishlist" do
    get work_url(@work)

    assert_response :success
    assert_select "summary", text: "Start reading"
    assert_select "summary", text: "Your copy: 1 owned"
    assert_select "label", text: /What became of it/
    assert_select "button", text: "Add to wishlist"
  end

  test "copies say what became of them" do
    Copy.create!(edition: @edition, disposition: "sold")

    get work_url(@work)

    assert_select "summary", text: "Your copies: 1 owned and 1 sold"
  end
end
