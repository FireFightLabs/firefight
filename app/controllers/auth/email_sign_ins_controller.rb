module Auth
  # Opening the link only shows a button, and the POST behind it signs in. Mail scanners that fetch every link would
  # otherwise use it up before the person clicks.
  class EmailSignInsController < InertiaController
    include SignInSession

    INVALID_EMAIL_MESSAGE = "Enter a valid email address.".freeze
    EXPIRED_MESSAGE = "That sign-in link has expired or was already used. Ask for a new one below.".freeze

    skip_before_action :block_suspended_workspace
    skip_before_action :require_authentication
    before_action :require_email_sign_in

    def create
      email = params[:email].to_s.strip.downcase
      unless EmailSignInService.valid_email?(email)
        return redirect_to(login_path, inertia: { errors: { email: [ INVALID_EMAIL_MESSAGE ] } })
      end

      EmailSignInService.new.request_link(
        email: email,
        link_url: ->(token) { email_sign_in_link_url(token: token) },
        requested_ip: request.remote_ip,
        user_agent: request.user_agent
      )
      session[:email_sign_in_sent_to] = email
      redirect_to email_sign_in_sent_path
    end

    def sent
      email = session[:email_sign_in_sent_to]
      return redirect_to(login_path) if email.blank?

      render inertia: "login/check-email", props: { email: email, minutes: LoginToken::LIFETIME.in_minutes.to_i }
    end

    def show
      render inertia: "login/confirm-email", props: {
        token: params[:token].to_s,
        usable: LoginToken.find_usable(params[:token]).present?,
        minutes: LoginToken::LIFETIME.in_minutes.to_i
      }
    end

    def consume
      result = EmailSignInService.new.sign_in(params[:token])
      return redirect_to(login_path, alert: EXPIRED_MESSAGE) unless result

      finish_self_serve_sign_in(result)
    end

    private

    def require_email_sign_in
      redirect_to(login_path, alert: OmniauthCallbacksController::UNAVAILABLE_MESSAGE) unless SignInMethods.email?
    end
  end
end
