require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  test "issue! returns a token record and the raw token, but only stores the digest" do
    user = users(:one)

    token, raw_token = ApiToken.issue!(user: user, name: "test client")

    assert_not_nil raw_token
    assert_equal ApiToken.digest(raw_token), token.token_digest
    assert_not_equal raw_token, token.token_digest
  end

  test "authenticate finds the token by its raw value and updates last_used_at" do
    user = users(:one)
    _token, raw_token = ApiToken.issue!(user: user, name: "test client")

    travel_to 1.hour.from_now do
      found = ApiToken.authenticate(raw_token)

      assert_not_nil found
      assert_in_delta Time.current.to_i, found.last_used_at.to_i, 1
    end
  end

  test "authenticate returns nil for an unknown token" do
    assert_nil ApiToken.authenticate("not-a-real-token")
  end

  test "authenticate returns nil for a blank token" do
    assert_nil ApiToken.authenticate("")
    assert_nil ApiToken.authenticate(nil)
  end
end
