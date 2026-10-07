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

  private

  # The address as written was checked when the account was validated. Where private networks are refused, the name
  # must also resolve to a public address, or a name pointing inside Firefight's network would pass.
  def guard_address!(account)
    address = account.settings.to_h[AiProviders::ADDRESS_SETTING]
    return if address.blank? || Entitlements.private_ai_endpoints?(@workspace)

    host = URI.parse(address).host.to_s
    return if AiAccountAddress.private_host?(host) || Webhooks::SsrfProtector.resolve_public_ip(host)

    account.errors.add(:base, "The API base URL does not resolve to a public address, which Firefight needs to reach it")
    raise ActiveRecord::RecordInvalid, account
  rescue URI::InvalidURIError, Resolv::ResolvError
    nil
  end
end
