# The workspace's own AI accounts, a card on Settings, Workspace. Admins only, never over the API or MCP. Saving checks
# the account with one call to its provider, so saves and checks are limited per workspace.
class AiAccountsController < InertiaController
  CHECKS_PER_MINUTE = 10
  TOO_MANY = "That is a lot of AI account changes at once. Wait a minute and try again.".freeze
  SIGN_IN_SESSION_KEY = :ai_account_sign_in

  authorizes Ability::Action::RESOURCE_AI_ACCOUNTS,
    create: %i[create sign_in sign_in_callback],
    update: %i[update reorder check disable enable],
    delete: :destroy

  rate_limit to: CHECKS_PER_MINUTE, within: 1.minute, by: -> { current_workspace&.id }, only: %i[create update check],
             with: -> { redirect_to settings_workspace_path, alert: TOO_MANY }

  before_action :set_account, only: %i[update destroy check disable enable]

  def create
    result = service.create!(provider: params[:provider], label: params[:label], settings: settings_param, models: models_param)
    checked(result, "#{result.account.label} was added")
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end

  def update
    result = service.update!(@account, label: params[:label], settings: settings_param, models: models_param)
    checked(result, "#{@account.label} was updated")
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: settings_workspace_path, inertia: { errors: e.record.errors.to_hash }
  end

  def check
    checked(service.check!(@account), "#{@account.label} was checked")
  end

  def disable
    @account.disable!
    redirect_to settings_workspace_path, notice: "#{@account.label} was turned off. Halon will skip it."
  end

  def enable
    @account.enable!
    redirect_to settings_workspace_path, notice: "#{@account.label} was turned on."
  end

  def destroy
    @account.destroy!
    redirect_to settings_workspace_path, notice: "#{@account.label} was deleted."
  end

  def reorder
    WorkspaceAiAccount.reorder!(current_workspace, Array(params.require(:ordered_ids)))
    redirect_to settings_workspace_path, notice: "AI account order updated."
  end

  # Sign in with ChatGPT, behind its feature flag. Only the state and the PKCE verifier wait in the session, never a token.
  def sign_in
    flow = AiAccountSignIn.new(current_workspace, by: current_membership).begin(redirect_uri: sign_in_callback_ai_accounts_url)
    session[SIGN_IN_SESSION_KEY] = flow[:pending]
    redirect_to flow[:url], allow_other_host: true
  rescue AiAccountSignIn::Failed => e
    redirect_to settings_workspace_path, alert: e.message
  end

  def sign_in_callback
    pending = session.delete(SIGN_IN_SESSION_KEY)
    result = AiAccountSignIn.new(current_workspace, by: current_membership)
                            .finish!(pending, code: params[:code].to_s, state: params[:state].to_s, redirect_uri: sign_in_callback_ai_accounts_url)
    checked(result, "#{result.account.label} was added")
  rescue AiAccountSignIn::Failed => e
    redirect_to settings_workspace_path, alert: e.message
  end

  private

  def service = WorkspaceAiAccountService.new(current_workspace, by: current_membership)

  def set_account
    @account = current_workspace.workspace_ai_accounts.find(params[:id])
  end

  def settings_param = params.fetch(:settings, {}).permit(*AiProviders.setting_keys).to_h.transform_values(&:to_s)

  def models_param = params.fetch(:models, {}).permit(*WorkspaceAiAccount::ROLES).to_h

  # The save stands either way. A failed check keeps the account out of Halon's way and says why.
  def checked(result, done)
    if result.checked?
      redirect_to settings_workspace_path, notice: "#{done} and works."
    else
      skipped = " Halon will skip it until a check passes." if result.account.skipped?
      redirect_to settings_workspace_path, alert: "#{done}, but the check failed. #{result.error}#{skipped}"
    end
  end
end
