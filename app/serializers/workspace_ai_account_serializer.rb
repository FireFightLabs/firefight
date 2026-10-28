# One of the workspace's own AI accounts on Settings, Workspace. It never carries the credentials, only the non-secret
# settings and a sentence saying how the key ends.
class WorkspaceAiAccountSerializer < BaseSerializer
  object_as :account

  STATE_UNION = WorkspaceAiAccount::STATES.map { |state| state.to_s.inspect }.join(" | ")

  type :string
  def id = account.id

  attributes(label: { type: :string }, provider: { type: :string }, kind: { type: :string }, enabled: { type: :boolean })

  # The settings table's shared row reads a name.
  type :string
  def name = account.label

  type :string
  def provider_name = account.subscription_definition&.plan || account.provider_definition&.name || account.provider

  type "{ main: string; fast: string }"
  def models = { main: account.model_for(WorkspaceAiAccount::MAIN).to_s, fast: account.model_for(WorkspaceAiAccount::FAST).to_s }

  # Only the settings that are not secrets, such as an address or a region.
  type "Record<string, string>"
  def settings
    secret = account.provider_definition&.secret_fields&.map(&:key).to_a
    account.settings.to_h.except(*secret)
  end

  type :string, optional: true
  def key_summary = account.credential_summary

  type STATE_UNION
  def state = account.state.to_s

  type :string, optional: true
  def last_error = account.last_error

  type :string, optional: true
  def verified_at = account.verified_at&.iso8601

  type :string, optional: true
  def last_used_at = account.last_used_at&.iso8601

  type :string
  def deletion_consequence = account.deletion_consequence

  # Why the account cannot be edited, checked or signed in again right now, or null when it can.
  type :string, optional: true
  def edit_blocked_reason = account.change_blocked_reason

  # What a subscription account adds: the plan, the models its sign-in serves, and its limit as the proxy last saw it.
  # leftPercent and resetsAt are null where the provider does not say.
  type "{ plan: string; models: { id: string; name: string }[]; leftPercent: number | null; resetsAt: string | null; reachedUntil: string | null } | null"
  def subscription
    return nil unless account.subscription?

    limit = account.proxy_limit
    {
      plan: account.subscription_definition&.plan.to_s,
      models: account.proxy_models.map { |model| { id: model["id"].to_s, name: model["name"].presence || model["id"].to_s } },
      leftPercent: limit["left_percent"],
      resetsAt: limit["resets_at"],
      reachedUntil: account.limit_reached? ? limit["reached_until"] : nil
    }
  end
end
