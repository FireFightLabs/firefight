# Sign-in by a link sent to an address. Asking for a link answers the same for every address, and the email is sent
# whether or not anyone holds it, so the page never says who has an account.
class EmailSignInService
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP
  MAX_EMAIL_LENGTH = 254

  def self.valid_email?(email)
    email.length <= MAX_EMAIL_LENGTH && EMAIL_FORMAT.match?(email)
  end

  # link_url turns the raw token into the address the email points at.
  def request_link(email:, link_url:, requested_ip: nil, user_agent: nil)
    token = LoginToken.issue!(email: email, requested_ip: requested_ip, user_agent: user_agent)
    SignInMailer.magic_link(email: email, url: link_url.call(token)).deliver_later
  end

  # Nil when the link is unknown, expired or already used.
  def sign_in(token)
    login_token = LoginToken.consume(token)
    return nil unless login_token

    claims = AuthenticationService::Claims.new(
      provider: UserIdentity::EMAIL, uid: login_token.email, email: login_token.email, email_verified: true
    )
    AuthenticationService.new.sign_in_with(claims)
  end
end
