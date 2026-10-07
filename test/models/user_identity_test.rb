require "test_helper"

class UserIdentityTest < ActiveSupport::TestCase
  setup do
    @alice = users(:alice)
    @slack = @alice.identities.create!(provider: UserIdentity::SLACK, uid: "T1/U1", email: " Alice@Example.com ")
  end

  test "an account is held by one person only" do
    duplicate = users(:bob).identities.build(provider: UserIdentity::SLACK, uid: "T1/U1")

    assert_not duplicate.valid?
  end

  test "the same id under another provider is a different account" do
    assert users(:bob).identities.build(provider: UserIdentity::GOOGLE, uid: "T1/U1").valid?
  end

  test "emails are stored lowercased and trimmed" do
    assert_equal "alice@example.com", @slack.email
  end

  test "the last method cannot be removed" do
    assert_equal UserIdentity::LAST_METHOD_REASON, @slack.removal_blocked_reason
    assert_raises(ActiveRecord::RecordNotDestroyed) { @slack.remove! }
    assert UserIdentity.exists?(@slack.id)
  end

  test "a method can be removed while another is left" do
    google = @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice")

    google.remove!

    assert_not UserIdentity.exists?(google.id)
    assert_equal UserIdentity::LAST_METHOD_REASON, @slack.reload.removal_blocked_reason
  end

  test "two removals read the methods left after taking the lock" do
    google = @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice")
    stale_slack = UserIdentity.find(@slack.id)
    stale_slack.user.identities.load

    google.remove!

    assert_raises(ActiveRecord::RecordNotDestroyed) { stale_slack.remove! }
    assert UserIdentity.exists?(@slack.id)
  end
end
