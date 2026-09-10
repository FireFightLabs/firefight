module Auth
  class OmniauthCallbacksController < ApplicationController
    skip_before_action :verify_authenticity_token, only: [ :slack, :slack_openid ]

    # Sign-in only, no bot install. AuthOutcome decides between signed in and the install
    # step, or the invite code step first when the gate is on.
    def slack_openid
      outcome = SlackAuthenticationService.new.handle_openid_signin(auth_hash)
      apply_outcome(outcome)
    rescue => e
      log_auth_failure(:slack_openid_failed, e)
      redirect_to login_path, alert: "Sign-in failed. Please try again."
    end

    # Bot install, creating the workspace and owner membership. The installer's identity comes
    # from the sign-in step as `pending_user_id`, since the install auth_hash's user info is brittle.
    def slack
      outcome = SlackAuthenticationService.new.handle_install(
        auth_hash,
        user: pending_user || current_user,
        invite_code: claimed_invite_code,
        pending_team_id: session[:pending_team_id]
      )
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

    def apply_outcome(outcome)
      return sign_in_and_redirect(outcome)       if outcome.signed_in?
      return start_install_and_redirect(outcome) if outcome.install_needed?
      return invite_required_and_redirect(outcome) if outcome.invite_required?

      raise "Unhandled auth outcome: #{outcome.inspect}"
    end

    def sign_in_and_redirect(outcome)
      # Captured before reset_session wipes it.
      return_to = safe_return_to(session[:return_to])
      reset_session
      session[:user_id]      = outcome.membership.user_id
      session[:workspace_id] = outcome.membership.workspace_id
      session[:show_welcome_note] = true if outcome.first_install?
      target = outcome.first_install? ? onboarding_welcome_path : (return_to || dashboard_path)
      redirect_to(target, notice: outcome.message)
    end

    def safe_return_to(path)
      return nil if path.blank?
      return nil unless path.is_a?(String) && path.start_with?("/app/")
      path
    end

    def start_install_and_redirect(outcome)
      session[:pending_user_id]   = outcome.user.id
      session[:pending_team_id]   = outcome.team_id
      session[:pending_team_name] = outcome.team_name
      redirect_to(InviteCode.required? ? onboarding_invite_code_path : onboarding_install_path)
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

    # Diagnostic context without tokens or emails. Rescued because auth_hash may be nil
    # and session access can raise mid-error.
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
