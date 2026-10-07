require "test_helper"

class UserIdentitiesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @alice = users(:alice)
    sign_in(@alice, workspaces(:slack_workspace_one))
    @slack = @alice.identities.create!(provider: UserIdentity::SLACK, uid: "T12345678/U12345678", email: @alice.email)
  end

  test "the profile lists every sign-in method with the reason any cannot be removed" do
    google = @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email)

    get profile_path, headers: inertia_headers

    methods = inertia_props["signInMethods"]
    assert_equal [ @slack.id, google.id ], methods.pluck("id")
    assert_equal [ "Slack", "Google" ], methods.pluck("label")
    assert methods.none? { |method| method["removalBlockedReason"] }
  end

  test "the only method shows why it cannot be removed" do
    get profile_path, headers: inertia_headers

    assert_equal UserIdentity::LAST_METHOD_REASON, inertia_props["signInMethods"].sole["removalBlockedReason"]
  end

  test "removing a method when another is left confirms with a toast" do
    google = @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email)

    delete sign_in_method_path(google)

    assert_redirected_to profile_path
    assert_equal "Google (alice@example.com) was removed from your sign-in methods.", flash[:notice]
    assert_not UserIdentity.exists?(google.id)
  end

  test "the last method is never removed" do
    delete sign_in_method_path(@slack)

    assert_redirected_to profile_path
    assert_equal UserIdentity::LAST_METHOD_REASON, flash[:alert]
    assert UserIdentity.exists?(@slack.id)
  end

  test "someone else's method cannot be removed" do
    bobs = users(:bob).identities.create!(provider: UserIdentity::GOOGLE, uid: "google-bob", email: users(:bob).email)

    delete sign_in_method_path(bobs)

    assert_response :not_found
    assert UserIdentity.exists?(bobs.id)
  end
end
