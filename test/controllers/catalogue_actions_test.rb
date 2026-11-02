require "test_helper"

# The book page's catalogue actions (docs/CATALOG.md, build step 5):
# the reading log, what each edition is to Mark, and wishlist membership.
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

  test "an edition's status and purchase details: sold, then not mine (read elsewhere), then owned again" do
    patch holding_work_edition_url(@work, @edition), params: { status: "sold", details: { acquired_date: "2026-11-02", acquired_price: "4.50", acquired_source: "eBay" } }
    assert_redirected_to work_path(@work)
    assert_equal [ "sold", BigDecimal("4.50"), "eBay" ], [ @copy.reload.disposition, @copy.acquired_price, @copy.acquired_source ]

    reading = Reading.create!(work: @work, edition: @edition, copy: @copy, status: "completed", source: "owned_copy", date_finished: Date.new(2025, 1, 1))
    patch holding_work_edition_url(@work, @edition), params: { status: "not_mine" }
    assert_empty @edition.copies.reload
    assert_nil reading.reload.copy
    assert_equal "not_mine", EditionHolding.status(@edition)

    patch holding_work_edition_url(@work, @edition), params: { status: "owned" }
    assert_equal "owned", @edition.copies.reload.sole.disposition
  end

  test "an unknown status is ignored, not an error" do
    patch holding_work_edition_url(@work, @edition), params: { status: "stolen" }

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

  test "the book page offers starting a read, each edition's status, and the wishlist" do
    get work_url(@work)

    assert_response :success
    assert_select "summary", text: "Start reading"
    assert_select "summary", text: /Owned\s+— change/
    assert_select "select[name=status] option[selected][value=owned]"
    assert_select "button", text: "Add to wishlist"
    assert_select "button", text: /Delete this edition/, count: 0 # its only edition
    assert_no_match(/\bcop(y|ies)\b/i, css_select("main").text)
  end

  test "deleting a duplicate edition: its readings move to the one kept, and its status goes with it" do
    dupe = Edition.create!(publisher: "Ace")
    EditionContent.create!(work: @work, edition: dupe)
    dupe_copy = Copy.create!(edition: dupe, disposition: "owned")
    reading = Reading.create!(work: @work, edition: dupe, copy: dupe_copy, status: "completed", source: "owned_copy", date_finished: Date.new(2025, 1, 1))
    decision = PendingDecision.create!(kind: "enrichment_conflict", payload: { entity_type: "Edition", entity_id: dupe.id, source: "isfdb", fields: [ "publisher" ] })

    get work_url(@work)
    assert_select "form[action=?] select[name=move_to] option[value=?]", work_edition_path(@work, dupe), @edition.id.to_s

    delete work_edition_url(@work, dupe), params: { move_to: @edition.id }

    assert_redirected_to work_path(@work)
    assert_not Edition.exists?(dupe.id)
    assert_not Copy.exists?(dupe_copy.id)
    assert_equal [ @edition, @copy ], [ reading.reload.edition, reading.copy ]
    assert decision.reload.rejected?
  end

  test "a book's only edition can't be deleted" do
    delete work_edition_url(@work, @edition)

    assert_equal "This is the book's only edition.", flash[:alert]
    assert Edition.exists?(@edition.id)
  end

  test "deleting a mistaken edition with its readings too; reviews stay with the book" do
    dupe = Edition.create!(publisher: "Ace")
    EditionContent.create!(work: @work, edition: dupe)
    reading = Reading.create!(work: @work, edition: dupe, status: "completed", source: "library", date_finished: Date.new(2025, 1, 1))
    review = Review.create!(work: @work, reading:, text: "Fine.", status: "draft")

    delete work_edition_url(@work, dupe), params: { move_to: "delete" }

    assert_not Reading.exists?(reading.id)
    assert_equal [ @work, nil ], [ review.reload.work, review.reading ]
  end
end
