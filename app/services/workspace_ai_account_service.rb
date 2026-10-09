# Saving a workspace's own AI account and checking it works, which calls the provider. A save always stores what the
# admin entered, then checks it with one tiny call on the account's quick model, ledgered as ai_account_check, so an
# account whose key is refused is kept out of Halon's way with the reason in plain words rather than lost.
class WorkspaceAiAccountService
  Result = Data.define(:account, :error) do
    def checked? = error.nil?
  end

  def initialize(workspace, by: nil)
    @workspace = workspace
    @by = by
  end

  def create!(provider:, label:, settings:, models:)
    account = @workspace.workspace_ai_accounts.new(provider: provider.to_s, label: label.to_s.strip, kind: AiProviders::KIND_API_KEY,
                                                   created_by: @by)
    account.assign_settings(settings)
    account.assign_models(models)
    guard_address!(account)
    account.save_in_position!
    check!(account)
  end

  def update!(account, label:, settings:, models:)
    account.label = label.to_s.strip
    account.assign_settings(settings)
    account.assign_models(models)
    guard_address!(account)
    account.save!
    check!(account)
  end

  # The account signed in through OAuth, such as Sign in with ChatGPT. Its tokens are its credentials.
  def connect_oauth!(provider:, tokens:, expires_at:, email:)
    definition = AiProviders.find(provider)
    account = @workspace.workspace_ai_accounts.new(provider: provider.to_s, kind: AiProviders::KIND_OAUTH, created_by: @by,
                                                   label: definition&.sign_in&.label.to_s.delete_prefix("Sign in with ").presence || provider.to_s)
    account.assign_models({})
    account.assign_tokens(tokens.to_h.merge("email" => email), expires_at: expires_at)
    account.save_in_position!
    check!(account)
  end

  # One tiny call. An answer clears whatever kept the account out of use, a refusal keeps it out with why.
  def check!(account)
    FirefightAi.check_account(account.choice_for(AiPurpose::SUMMARY), workspace: @workspace)
    Result.new(account: account.checked!, error: nil)
  rescue *AiAccountError::CHECK_ERRORS => e
    Result.new(account: account.check_failed!(e), error: account.last_error)
  end

  # A direct message to each admin and owner, through the workspace's platform, saying which account stopped and what
  # Halon does now.
  def notify_admins!(account, notice)
    text = notice_text(account, notice)
    adapter = WorkspaceAdapter.for(@workspace)
    @workspace.workspace_memberships.admins_and_owners.where.not(platform_user_id: nil).find_each do |admin|
      adapter.post_direct_message(user_id: admin.platform_user_id, text: text)
    rescue AdapterError => e
      Rails.logger.warn({ event: "ai_account.notice_failed", account_id: account.id, error: e.class.name }.to_json)
    end
    Rails.logger.info({ event: "ai_account.noticed", account_id: account.id, notice: notice }.to_json)
  end

  def notice_text(account, notice)
    what = notice == WorkspaceAiAccount::NOTICE_KEY_REFUSED ? "had its key refused" : "ran out of credit"
    following = AiFunding.for(@workspace, AiPurpose::INVESTIGATION).any?
    next_step = following ? "Halon is using the next one in the list." : "Halon has no other account to use, so it cannot answer until this is fixed."
    link = settings_link
    where = link ? "Fix it under Settings, Workspace, AI accounts: #{link}" : "Fix it under Settings, Workspace, AI accounts."
    "Halon's AI account \"#{account.label}\" #{what}. #{next_step} #{where}"
  end

  private

  def settings_link
    options = AppUrl.options
    options && Rails.application.routes.url_helpers.settings_workspace_url(**options)
  end

  # The address as written was checked when the account was validated, which also says why a private one is refused.
  # Where private networks are refused, the name must also resolve to an address every call may reach, checked the
  # same way as before each call (Integrations::ModelAddress), so a name pointing inside Firefight's network never saves.
  def guard_address!(account)
    address = account.settings.to_h[AiProviders::ADDRESS_SETTING]
    return if address.blank? || Entitlements.private_ai_endpoints?(@workspace)

    host = URI.parse(address).host.to_s
    return if AiAccountAddress.private_host?(host)

    Integrations::ModelAddress.ip_for!(host)
  rescue Integrations::ModelAddress::Refused => e
    account.errors.add(:base, e.message)
    raise ActiveRecord::RecordInvalid, account
  rescue URI::InvalidURIError
    nil
  end
end
