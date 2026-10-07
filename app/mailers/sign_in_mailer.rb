class SignInMailer < ApplicationMailer
  def magic_link(email:, url:)
    @url = url
    @minutes = LoginToken::LIFETIME.in_minutes.to_i
    mail(to: email, subject: "Your Firefight sign-in link")
  end

  def new_method(identity)
    @method_name = identity.label
    @identity_email = identity.email
    @added_at = identity.created_at
    @profile_url = profile_url
    mail(to: identity.user.email, subject: "A new way to sign in was added to your Firefight account")
  end
end
