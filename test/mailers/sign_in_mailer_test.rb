require "test_helper"

class SignInMailerTest < ActionMailer::TestCase
  test "the sign-in link email carries the link and how long it lasts" do
    mail = SignInMailer.magic_link(email: "person@example.com", url: "https://app.example.com/auth/email/confirm?token=abc")

    assert_equal [ "person@example.com" ], mail.to
    assert_equal "Your Firefight sign-in link", mail.subject
    assert_match "https://app.example.com/auth/email/confirm?token=abc", mail.text_part.body.to_s
    assert_match "https://app.example.com/auth/email/confirm?token=abc", mail.html_part.body.to_s
    assert_match "next 15 minutes", mail.text_part.body.to_s
  end

  test "the new method email names the method and links to the profile" do
    alice = users(:alice)
    identity = alice.identities.create!(provider: UserIdentity::GOOGLE, uid: "google-alice", email: "alice@gmail.example")

    mail = SignInMailer.new_method(identity)

    assert_equal [ alice.email ], mail.to
    assert_equal "A new way to sign in was added to your Firefight account", mail.subject
    assert_match "Google (alice@gmail.example) can now be used to sign in", mail.text_part.body.to_s
    assert_match "http://example.com/app/profile", mail.text_part.body.to_s
  end
end
