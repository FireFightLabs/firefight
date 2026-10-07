require "test_helper"

class AuthenticationServiceTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @service = AuthenticationService.new
    @alice = users(:alice)
    @bob = users(:bob)
  end

  test "an account already linked signs in as its person, whatever email it now carries" do
    identity = @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email, email_verified: true)

    result = @service.sign_in_with(claims(uid: "google-alice", email: @bob.email))

    assert result.signed_in?
    assert_equal @alice, result.user
    assert_equal identity, result.identity
    assert_equal @bob.email, identity.reload.email
    assert_equal "alice@example.com", @alice.reload.email, "the person's own email never follows the provider"
    assert_nil @bob.identities.find_by(provider: UserIdentity::GOOGLE)
  end

  test "an email change at the provider never moves the account to whoever holds the new address" do
    @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email, email_verified: true)
    @service.sign_in_with(claims(uid: "google-alice", email: "alice.new@example.com"))

    result = @service.sign_in_with(claims(uid: "google-alice", email: @bob.email))

    assert_equal @alice, result.user
  end

  test "a verified email links a new account to the person who holds it" do
    result = @service.sign_in_with(claims(uid: "google-new", email: "Alice@Example.com "))

    assert result.signed_in?
    assert_equal @alice, result.user
    assert_equal @alice, UserIdentity.find_by!(provider: UserIdentity::GOOGLE, uid: "google-new").user
  end

  test "an unverified email never links to the person who holds it" do
    result = @service.sign_in_with(claims(uid: "slack-unverified", email: @alice.email, email_verified: false))

    assert result.unverified_email?
    assert_nil result.user
    assert_not UserIdentity.exists?(uid: "slack-unverified")
  end

  test "an unverified email never creates a person either" do
    result = @service.sign_in_with(claims(uid: "nobody", email: "nobody@example.com", email_verified: false), create_user: true)

    assert result.unverified_email?
    assert_nil User.find_by(email: "nobody@example.com")
  end

  test "require_verified_email refuses an unverified email even from a linked account" do
    @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email, email_verified: true)

    result = @service.sign_in_with(claims(uid: "google-alice", email: @alice.email, email_verified: false), require_verified_email: true)

    assert result.unverified_email?
  end

  test "an unknown verified email reaches nobody unless asked to create the person" do
    result = @service.sign_in_with(claims(uid: "google-stranger", email: "stranger@example.com"))

    assert result.no_account?
    assert_nil User.find_by(email: "stranger@example.com")
    assert_not UserIdentity.exists?(uid: "google-stranger")
  end

  test "create_user makes the person and their first sign-in method" do
    result = @service.sign_in_with(claims(uid: "google-stranger", email: "Stranger@Example.com", name: "Stranger"), create_user: true)

    assert result.signed_in?
    assert_equal "stranger@example.com", result.user.email
    assert_equal "Stranger", result.user.name
    assert_equal [ "google-stranger" ], result.user.identities.pluck(:uid)
  end

  test "adding a method to a person who already has one emails them" do
    @alice.identities.create!(provider: UserIdentity::SLACK, uid: "T1/U1", email: @alice.email)

    assert_enqueued_email_with SignInMailer, :new_method, args: ->(args) { args.first.uid == "google-new" } do
      @service.sign_in_with(claims(uid: "google-new", email: @alice.email))
    end
  end

  test "a person's first method sends no email, and a returning sign-in sends none" do
    assert_no_enqueued_emails do
      @service.sign_in_with(claims(uid: "google-first", email: @alice.email))
      @service.sign_in_with(claims(uid: "google-first", email: @alice.email))
    end
  end

  test "no email is sent when this host cannot send mail" do
    @alice.identities.create!(provider: UserIdentity::SLACK, uid: "T1/U1", email: @alice.email)
    MailDelivery.stubs(:configured?).returns(false)

    assert_no_enqueued_emails do
      assert @service.sign_in_with(claims(uid: "google-new", email: @alice.email)).signed_in?
    end
  end

  test "a returning sign-in records when the method was last used" do
    identity = @alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: @alice.email)

    freeze_time do
      @service.sign_in_with(claims(uid: "google-alice", email: @alice.email))
      assert_equal Time.current, identity.reload.last_used_at
    end
  end

  test "refresh_profile takes the provider's name and avatar, otherwise only blanks are filled" do
    @service.sign_in_with(claims(uid: "google-alice", email: @alice.email, name: "Someone Else", avatar_url: "https://example.com/new.png"))
    assert_equal "Alice Smith", @alice.reload.name

    @service.sign_in_with(claims(uid: "google-alice", email: @alice.email, name: "Alice S.", avatar_url: "https://example.com/new.png"), refresh_profile: true)
    assert_equal "Alice S.", @alice.reload.name
    assert_equal "https://example.com/new.png", @alice.avatar_url
  end

  private

  def claims(uid:, email:, email_verified: true, name: nil, avatar_url: nil, provider: UserIdentity::GOOGLE)
    AuthenticationService::Claims.new(provider: provider, uid: uid, email: email, email_verified: email_verified, name: name, avatar_url: avatar_url)
  end
end
