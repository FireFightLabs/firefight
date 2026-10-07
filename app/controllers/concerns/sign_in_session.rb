# Every method starts a session the same way, with a fresh session id and the page the person was sent away from
# kept across the reset.
module SignInSession
  extend ActiveSupport::Concern

  private

  def start_session(user_id:, workspace_id:)
    return_to = safe_return_to(session[:return_to])
    reset_session
    session[:user_id] = user_id
    session[:workspace_id] = workspace_id
    return_to
  end

  # Signed in through Google or email. A person with no workspace yet waits on the signup page.
  def finish_self_serve_sign_in(result)
    membership = result.user&.workspace_memberships&.order(joined_at: :desc)&.first
    return redirect_to(onboarding_signup_path) unless membership

    return_to = start_session(user_id: membership.user_id, workspace_id: membership.workspace_id)
    redirect_to(return_to || dashboard_path)
  end

  def safe_return_to(path)
    return nil if path.blank?
    return nil unless path.is_a?(String) && path.start_with?("/app/")

    path
  end
end
