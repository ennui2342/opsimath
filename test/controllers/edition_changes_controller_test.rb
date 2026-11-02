require "test_helper"

class EditionChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @work = Work.create!(title: "The Anubis Gates", literary_form: "novel")
    @edition = Edition.create!(publisher: "HarperCollins", publish_date: "1993")
    EditionContent.create!(work: @work, edition: @edition)
    @edition.edition_identifiers.create!(id_type: "isbn13", value: Isbn.to_13("0586065504"))
    @edition.edition_identifiers.create!(id_type: "isfdb", value: "111")
    @work.provider_editions.create!(provider: "isfdb", provider_id: "111", publisher: "HarperCollins", publish_date: "1993", binding: "pb", isbn10: "0586065504")
    @work.provider_editions.create!(provider: "isfdb", provider_id: "333", publisher: "Ace", publish_date: "1983", binding: "pb", isbn10: "0441023827")
    @choice = PendingDecision.create!(kind: "enrichment_printing_choice", payload: {
      entity_type: "Edition", entity_id: @edition.id, source: "isfdb", isbn: "0586065504",
      candidates: [ { "_isfdb_pub_id" => 111, "publisher" => "HarperCollins", "isbn_10" => "0586065504", "binding" => "pb", "publish_date" => "1993" },
                    { "_isfdb_pub_id" => 222, "publisher" => "Triad Grafton", "isbn_10" => "0586065504", "binding" => "pb", "publish_date" => "1986" } ]
    })
  end

  test "the book page asks which printing, and links every edition to the picker" do
    get work_url(@work)

    assert_select "a[href=?]", edit_work_edition_change_path(@work, @edition), text: "Which is yours?"
    assert_select "a[href=?]", edit_work_edition_change_path(@work, @edition), text: "Not this edition?"
  end

  test "the picker shows known editions plus the decision's candidates, same-ISBN and current first" do
    get edit_work_edition_change_url(@work, @edition)

    assert_response :success
    labels = css_select("label:has(input[name=card])").map { |l| l.text.squish }
    assert_equal 3, labels.size
    assert_match(/Yours now.*Same ISBN.*HarperCollins/, labels[0])
    assert_match(/Same ISBN.*Triad Grafton/, labels[1])
    assert_match(/Ace/, labels[2])
  end

  test "choosing re-points the edition and settles the decision" do
    get edit_work_edition_change_url(@work, @edition)
    triad = css_select("label:has(input[name=card])").find { |l| l.text.include?("Triad") }.at_css("input")["value"]

    patch work_edition_change_url(@work, @edition), params: { card: triad }

    assert_redirected_to work_path(@work)
    assert_equal [ "Triad Grafton", "1986" ], [ @edition.reload.publisher, @edition.publish_date ]
    assert @choice.reload.accepted?
  end

  test "an edition of another work isn't reachable" do
    other = Work.create!(title: "Other", literary_form: "novel")

    get edit_work_edition_change_url(other, @edition)

    assert_response :not_found
  end
end
