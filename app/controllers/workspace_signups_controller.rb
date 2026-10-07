# Naming a new workspace, after a sign-in that reached nobody with one. Whoever signed in is held in the session
# (SignInSession#start_signup) until the workspace exists, and only then signed in to the dashboard.
class WorkspaceSignupsController < InertiaController
  include SignInSession

  INVALID_CODE_MESSAGE = "That invite code is invalid or expired.".freeze

  skip_before_action :block_inaccessible_workspace
  skip_before_action :require_authentication
  before_action :require_self_serve
  before_action :require_signup

  def new
    render inertia: "signup/workspace", props: {
      email: signup_user&.email || signup_claims.email,
      suggestedName: session[:signup_team_name].to_s,
      nameMaxLength: Workspace::NAME_MAX_LENGTH,
      inviteRequired: InviteCode.required?,
      askName: asks_name?
    }
  end

  def create
    invite_code = InviteCode.find_active_by_code(params[:invite_code]) if InviteCode.required?
    return invalid_code if InviteCode.required? && invite_code.nil?

    return missing_person_name if asks_name? && params[:person_name].to_s.strip.empty?

    claims = signup_claims && (asks_name? ? signup_claims.with(name: params[:person_name].to_s.strip.first(100)) : signup_claims)
    membership = WorkspaceSignupService.new.create(
      name: params[:name], user: signup_user, claims: claims, invite_code: invite_code
    )
    redirect_to signed_up(membership)
  rescue InviteCode::RedemptionError
    invalid_code
  rescue ActiveRecord::RecordInvalid => e
    redirect_to signup_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end

  private

  def require_self_serve
    redirect_to(login_path) unless SignInMethods.self_serve?
  end

  def require_signup
    return if signup_user || signup_claims

    redirect_to(user_signed_in? ? dashboard_path : login_path)
  end

  def signup_user
    return @signup_user if defined?(@signup_user)

    @signup_user = session[:signup_user_id] && User.find_by(id: session[:signup_user_id])
  end

  def signup_claims
    return @signup_claims if defined?(@signup_claims)

    stored = session[:signup_claims]
    @signup_claims = stored.is_a?(Hash) && !signup_user ? AuthenticationService::Claims.new(**stored.symbolize_keys) : nil
  end

  # A Slack sign-in already named its team, so the welcome continues straight to connecting it.
  def signed_up(membership)
    team_id = session[:signup_team_id]
    team_name = session[:signup_team_name]
    start_session(user_id: membership.user_id, workspace_id: membership.workspace_id)
    session[:show_welcome_note] = true
    if team_id.present?
      session[:connecting_workspace_id] = membership.workspace_id
      session[:pending_user_id] = membership.user_id
      session[:pending_team_id] = team_id
      session[:pending_team_name] = team_name
    end
    Entitlements.next_step_path(membership.workspace) || onboarding_welcome_path
  end

  # An email link carries no name, so someone new by email says what to call them.
  def asks_name?
    signup_claims.present? && signup_claims.name.blank?
  end

  def missing_person_name
    redirect_to signup_workspace_path, inertia: { errors: { person_name: [ "Enter your name." ] } }
  end

  def invalid_code
    redirect_to signup_workspace_path, inertia: { errors: { invite_code: [ INVALID_CODE_MESSAGE ] } }
  end
end
