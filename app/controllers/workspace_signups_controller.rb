# Naming a new workspace, after a sign-in that reached nobody with one. Whoever signed in is held in the session
# (SignInSession#start_signup) until the workspace exists, and only then signed in to the dashboard. A Slack sign-in by
# someone who owns workspaces without Slack, even just one, chooses one of them here first, or says to make another.
class WorkspaceSignupsController < InertiaController
  include SignInSession

  INVALID_CODE_MESSAGE = "That invite code is invalid or expired.".freeze
  UNKNOWN_WORKSPACE_MESSAGE = "That workspace is not one you can connect. Choose another.".freeze

  skip_before_action :block_inaccessible_workspace
  skip_before_action :require_authentication
  skip_before_action :continue_setup
  before_action :require_self_serve
  before_action :require_signup

  def new
    render inertia: "signup/workspace", props: {
      email: signup_user&.email || signup_claims.email,
      suggestedName: session[:signup_team_name].to_s,
      nameMaxLength: Workspace::NAME_MAX_LENGTH,
      inviteRequired: InviteCode.required?,
      askName: asks_name?,
      unconnectedWorkspaces: unconnected_memberships.map do |membership|
        { id: membership.workspace_id, name: membership.workspace.name, createdAt: membership.workspace.created_at.utc.iso8601 }
      end
    }
  end

  # A Slack sign-in by someone who owns workspaces without Slack, carrying on in the one they chose.
  def reuse
    membership = unconnected_memberships.find { |candidate| candidate.workspace_id == params[:workspace_id] }
    return redirect_to(signup_workspace_path, alert: UNKNOWN_WORKSPACE_MESSAGE) unless membership

    continue_in_unconnected(membership, team_id: session[:signup_team_id], team_name: session[:signup_team_name])
  end

  def create
    # Someone with workspaces to choose from makes another only by saying so.
    return redirect_to(signup_workspace_path) if unconnected_memberships.any? && params[:create_new].blank?

    invite_code = InviteCode.find_active_by_code(params[:invite_code]) if InviteCode.required?
    return invalid_code if InviteCode.required? && invite_code.nil?

    return missing_person_name if asks_name? && params[:person_name].to_s.strip.empty?

    claims = signup_claims && (asks_name? ? signup_claims.with(name: params[:person_name].to_s.strip.first(100)) : signup_claims)
    membership = WorkspaceSignupService.new.create(
      name: params[:name], user: signup_user, claims: claims, invite_code: invite_code,
      sign_up_method: session[:signup_method]
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

  # Only a Slack sign-in from a team no workspace has yet offers the workspaces this person owns without Slack. A
  # sign-in by Google or email reaches signup only with no workspace at all.
  def unconnected_memberships
    return @unconnected_memberships if defined?(@unconnected_memberships)

    @unconnected_memberships = signup_user && session[:signup_team_id].present? ? signup_user.owned_unconnected_memberships.to_a : []
  end

  # A Slack sign-in already named its team, so the welcome continues straight to connecting it.
  def signed_up(membership)
    team_id = session[:signup_team_id]
    team_name = session[:signup_team_name]
    start_session(user_id: membership.user_id, workspace_id: membership.workspace_id)
    hold_team_to_connect(membership, team_id: team_id, team_name: team_name) if team_id.present?
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
