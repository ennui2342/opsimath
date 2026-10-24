require "test_helper"

module Settings
  class CollectingProfilesControllerTest < ActionDispatch::IntegrationTest
    setup do
      @profile = CollectingProfile.create!(favourite_artist_min_owned: 2, favourite_artists_never: [ "Old Studio" ])
      [ "Chris Moore", "Chris Moore", "Blacksheep", "Blacksheep", "Jim Burns" ].each do |artist|
        Copy.create!(edition: Edition.create!(format: "paperback", cover_artist: artist), disposition: "owned")
      end
      sign_in_as users(:one)
    end

    test "settings index links to the collecting profile" do
      get "/settings"

      assert_response :success
      assert_select "a[href=?]", settings_collecting_profile_path
    end

    test "shows the artists at or above the threshold with their owned counts" do
      get settings_collecting_profile_url

      assert_response :success
      assert_select "input[name='not_favourite[]'][value='Chris Moore']"
      assert_select "input[name='not_favourite[]'][value='Blacksheep']"
      assert_select "input[name='not_favourite[]'][value='Jim Burns']", count: 0 # owns 1, threshold 2
    end

    test "saving updates the numbers and both lists, keeping never entries not shown" do
      patch settings_collecting_profile_url, params: {
        recent_years: "3", favourite_artist_min_owned: "2",
        shown_artists: [ "Chris Moore", "Blacksheep" ], not_favourite: [ "Blacksheep" ],
        favourite_artists_always: "Richard Powers\n\n  Bruce Pennington \nRichard Powers"
      }

      assert_redirected_to settings_collecting_profile_path
      @profile.reload
      assert_equal 3, @profile.recent_years
      assert_equal [ "Bruce Pennington", "Richard Powers" ], @profile.favourite_artists_always.sort
      assert_equal [ "Blacksheep", "Old Studio" ], @profile.favourite_artists_never.sort
      assert_equal [ "Bruce Pennington", "Chris Moore", "Richard Powers" ], @profile.favourite_artists.sort
    end

    test "unticking a never-list artist that's shown takes them off it" do
      @profile.update!(favourite_artists_never: [ "Blacksheep" ])

      patch settings_collecting_profile_url, params: { recent_years: "5", favourite_artist_min_owned: "2",
                                                        shown_artists: [ "Chris Moore", "Blacksheep" ] }

      assert_empty @profile.reload.favourite_artists_never
    end

    test "an invalid number re-renders with the error" do
      patch settings_collecting_profile_url, params: { recent_years: "-1", favourite_artist_min_owned: "0" }

      assert_response :unprocessable_entity
      assert_equal 5, @profile.reload.recent_years
    end
  end
end
