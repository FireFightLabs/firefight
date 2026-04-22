module Auth
  class OmniauthCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [ :slack, :slack_openid ]

    # Step 1 — OIDC sign-in (identity only). Decides where to send the user
    # next via AuthOutcome: signed_in (existing or newly-provisioned member) or
    # install_needed (no workspace for this team yet — sends them to the invite
    # code step before the install callback).
    def slack_openid
      outcome = SlackAuthenticationService.new.handle_openid_signin(auth_hash)
      apply_outcome(outcome)
    rescue => e
      log_auth_failure(:slack_openid_failed, e)
      redirect_to login_path, alert: "Sign-in failed. Please try again."
    end

    # Step 2 — bot install. Creates the workspace + owner membership.
    # The installer's identity was established in step 1 (OIDC) and stashed in
    # session as `pending_user_id`; we pass that user through so the install
    # callback doesn't re-derive identity from the bot install's auth_hash
    # (whose user_info / email fetch is brittle and not required here).
    def slack
      outcome = SlackAuthenticationService.new.handle_install(auth_hash, user: pending_user, invite_code: claimed_invite_code)
      apply_outcome(outcome)
    rescue => e
      log_auth_failure(:slack_install_failed, e)
      redirect_to login_path, alert: "Installation failed. Please try again."
    end

    def failure
      error_message = case params[:message]
      when "csrf_detected"
        "Authentication session expired. Please try again."
      when "access_denied"
        "You denied access to your Slack account."
      when "invalid_credentials"
        "Invalid credentials. Please contact support."
      else
        "Authentication failed. Please try again."
      end

      redirect_to login_path, alert: error_message
    end

    private

    def auth_hash
      request.env["omniauth.auth"]
    end

    def pending_user
      id = session[:pending_user_id]
      User.find_by(id: id) if id
    end

    # Maps an AuthOutcome to the right HTTP response. Keeps actions thin.
    def apply_outcome(outcome)
      return sign_in_and_redirect(outcome)       if outcome.signed_in?
      return start_install_and_redirect(outcome) if outcome.install_needed?
      return invite_required_and_redirect(outcome) if outcome.invite_required?

      raise "Unhandled auth outcome: #{outcome.inspect}"
    end

    def sign_in_and_redirect(outcome)
      session[:user_id]      = outcome.membership.user_id
      session[:workspace_id] = outcome.membership.workspace_id
      session[:show_welcome_note] = true if outcome.first_install?
      # Existing members do not consume invite capacity, but any stale claim
      # should still be cleared once sign-in succeeds.
      clear_pending_session_keys
      redirect_to(outcome.first_install? ? onboarding_welcome_path : dashboard_path, notice: outcome.message)
    end

    def start_install_and_redirect(outcome)
      session[:pending_user_id]   = outcome.user.id
      session[:pending_team_id]   = outcome.team_id
      session[:pending_team_name] = outcome.team_name
      redirect_to onboarding_invite_code_path
    end

    def clear_pending_session_keys
      %i[pending_user_id pending_team_id pending_team_name invite_code_id].each do |key|
        session.delete(key)
      end
    end

    def invite_required_and_redirect(outcome)
      clear_pending_session_keys
      redirect_to login_path, alert: outcome.message
    end

    def log_auth_failure(event, error)
      Rails.logger.error({
        event: "auth.#{event}",
        error: error.message,
        backtrace: error.backtrace&.first(5)
      })
    end
  end
end
