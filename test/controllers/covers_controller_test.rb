require "test_helper"

class CoversControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:one)
    @dir = Dir.mktmpdir
    @was = ENV["COVER_CACHE_DIR"]
    ENV["COVER_CACHE_DIR"] = @dir
    @url = "https://www.isfdb.org/wiki/images/8/81/BKTG00707.jpg"
  end

  teardown do
    ENV["COVER_CACHE_DIR"] = @was
    FileUtils.remove_entry(@dir)
  end

  test "a cached cover is served from disk, cacheable" do
    HasCoverImage.cache_write(@url, "JPEGBYTES", "BKTG00707.jpg", "image/jpeg")

    get cover_url(u: @url)

    assert_response :success
    assert_equal "JPEGBYTES", response.body
    assert_equal "image/jpeg", response.media_type
    assert_match(/max-age=\d{8}, public/, response.headers["Cache-Control"]) # a year
  end

  test "a cover not cached yet: the browser goes to the provider while it's fetched into the cache" do
    assert_enqueued_with(job: CoverCacheFetchJob, args: [ @url ]) { get cover_url(u: @url) }
    assert_redirected_to @url

    stub_request(:get, @url).to_return(status: 200, body: "JPEGBYTES", headers: { "Content-Type" => "image/jpeg" })
    perform_enqueued_jobs
    assert HasCoverImage.cached?(@url)
  end

  test "only known cover hosts: not an open proxy" do
    get cover_url(u: "http://169.254.169.254/latest/meta-data")
    assert_response :bad_request
  end

  test "cover_src goes through the proxy for a known host, and leaves anything else" do
    helper = ApplicationController.helpers
    assert_equal "/cover?u=#{CGI.escape(@url)}", helper.cover_src(@url)
    assert_equal "/rails/active_storage/x.jpg", helper.cover_src("/rails/active_storage/x.jpg")
    assert_nil helper.cover_src("")
  end

  test "nightly warming: owned and wanted books' printings' covers, into the cache" do
    work = Work.create!(title: "Sphere", literary_form: "novel")
    edition = Edition.create!
    EditionContent.create!(work:, edition:)
    Copy.create!(edition:, disposition: "owned")
    work.provider_editions.create!(provider: "isfdb", provider_id: "31670", cover_url: @url)
    stub_request(:get, @url).to_return(status: 200, body: "JPEGBYTES", headers: { "Content-Type" => "image/jpeg" })

    assert_equal 1, CoverCacheWarmJob.perform_now
    assert HasCoverImage.cached?(@url)
    assert_equal 0, CoverCacheWarmJob.perform_now # done once
  end
end
