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
      log_omniauth_failure

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
      Rails.logger.error(auth_failure_payload(event, error).to_json)
    end

    # OmniAuth's /auth/failure handler — logs the underlying error from
    # request.env["omniauth.error"] so we can see exactly what Slack rejected
    # (PKCE mismatch, invalid_grant, etc.) instead of just the generic message.
    def log_omniauth_failure
      omniauth_error = request.env["omniauth.error"]
      payload = {
        event: "auth.omniauth_failure",
        message:                params[:message],
        strategy:               request.env["omniauth.error.strategy"]&.name,
        error_class:            omniauth_error&.class&.name,
        error_message:          omniauth_error&.message,
        error_response_body:    extract_error_response_body(omniauth_error),
        backtrace:              omniauth_error&.backtrace&.first(20),
        cause_class:            omniauth_error&.cause&.class&.name,
        cause_message:          omniauth_error&.cause&.message,
        pkce_verifier_present:  session["omniauth.pkce.verifier"].present?
      }
      Rails.logger.error(payload.to_json)
    rescue StandardError => e
      Rails.logger.error({ event: "auth.omniauth_failure_logging_failed", error: e.message }.to_json)
    end

    # OAuth2::Error wraps the upstream HTTP response — extract its body so we
    # can see Slack's actual error code (invalid_grant, invalid_client, etc.)
    def extract_error_response_body(error)
      return nil unless error.respond_to?(:response) && error.response

      body = error.response.respond_to?(:body) ? error.response.body : error.response
      body.is_a?(String) ? body[0, 1000] : body.inspect[0, 1000]
    rescue StandardError
      nil
    end

    def auth_failure_payload(event, error)
      {
        event: "auth.#{event}",
        error_class: error.class.name,
        error_message: error.message,
        backtrace: error.backtrace&.first(20),
        cause_class: error.cause&.class&.name,
        cause_message: error.cause&.message,
        cause_backtrace: error.cause&.backtrace&.first(10),
        context: auth_failure_context
      }
    end

    # Session + auth_hash context that helps diagnose install failures without
    # leaking tokens or emails. Wrapped in a rescue because auth_hash may be nil
    # on some pre-callback failures and session access can raise mid-error.
    def auth_failure_context
      hash = auth_hash
      {
        pending_user_id_present:   session[:pending_user_id].present?,
        pending_team_id:           session[:pending_team_id],
        invite_code_id_present:    session[:invite_code_id].present?,
        auth_hash_present:         hash.present?,
        slack_uid_present:         hash&.uid.present?,
        slack_team_id:             hash&.dig("extra", "team_info", "id") || hash&.info&.team_id,
        slack_scopes_present:      hash&.credentials&.scope.present?
      }
    rescue StandardError => e
      { context_error: "#{e.class.name}: #{e.message}" }
    end
  end
end
