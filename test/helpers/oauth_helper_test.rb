require "test_helper"

class OauthHelperTest < ActionView::TestCase
  PreAuth = Struct.new(:redirect_uri)

  test "a loopback address reads as an app on this computer, and any other host as itself" do
    assert_equal "an app on this computer (localhost:33418)", oauth_destination(PreAuth.new("http://localhost:33418/callback"))
    assert_equal "claude.ai", oauth_destination(PreAuth.new("https://claude.ai/api/mcp/auth_callback"))
  end

  test "an address with no host, such as an app's own scheme, is shown whole" do
    assert_equal "cursor:/oauth/callback", oauth_destination(PreAuth.new("cursor:/oauth/callback"))
  end
end
