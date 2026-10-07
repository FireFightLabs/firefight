# What lets one coding agent in the sandbox reach a model for one code change, through Firefight's model proxy. The
# token is the only credential the box ever holds. It reaches one model, until a budget is spent or the session ends,
# and Firefight's own provider key never leaves Firefight.
class CodeAgentSession < ApplicationRecord
  # A coding agent asks the model many times on one change, so the budget covers the change, not a call.
  DEFAULT_BUDGET_MICROS = 2_000_000
  LIFETIME = 30.minutes
  TOKEN_BYTES = 32
  FEATURE = "code_fix".freeze
  OVER_BUDGET = "This code change has used its model budget.".freeze
  ENDED = "This code change's session has ended.".freeze
  # A coding agent asks one thing at a time, so more at once is something else using the token.
  MAX_CALLS_AT_ONCE = 3
  TOO_MANY_AT_ONCE = "This code change already has #{MAX_CALLS_AT_ONCE} model calls running.".freeze

  belongs_to :workspace
  # The workspace's own AI account that pays for this change, when one does.
  belongs_to :workspace_ai_account, optional: true

  scope :live, -> { where(closed_at: nil).where("expires_at > ?", Time.current) }

  # The session and the token the box sends, which is shown once and kept only as a digest.
  def self.open!(workspace:, choice:, repository:, budget_micros: DEFAULT_BUDGET_MICROS)
    token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    payer = choice.payer || AiPayer.deployment(workspace)
    session = create!(workspace: workspace, provider: choice.provider_name, model: choice.model, repository: repository,
                      budget_micros: budget_micros, expires_at: LIFETIME.from_now, token_digest: digest(token),
                      paid_by: payer.paid_by, workspace_ai_account: payer.account)
    [ session, token ]
  end

  def self.authenticate(token)
    return if token.blank?

    live.find_by(token_digest: digest(token))
  end

  def self.digest(token) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)

  def over_budget? = spent_micros >= budget_micros

  # A provider refusing the key itself, rather than the request.
  KEY_REFUSED_STATUSES = [ 401, 403 ].freeze
  ACCOUNT_GONE = "The AI account paying for this code change was removed.".freeze

  def payer = AiPayer.new(paid_by: paid_by || AiPayer.deployment(workspace).paid_by, account: workspace_ai_account)

  # The configuration the model proxy forwards with: the paying account's own, or the deployment's. Nil means the
  # deployment's, and an account removed since the change began is never replaced by it.
  def llm_config
    return nil unless paid_by == Inference::PAID_BY_ACCOUNT
    raise FirefightAi::ModelProxy::Refused, ACCOUNT_GONE unless workspace_ai_account&.enabled

    workspace_ai_account.llm_context.config
  end

  # Added in SQL, so two calls the agent makes at once are both counted.
  def charge!(micros)
    self.class.where(id: id).update_all([ "spent_micros = spent_micros + ?, updated_at = ?", micros.to_i, Time.current ])
    reload
  end

  # Claims a place for one call, in SQL, so calls at once cannot all slip past the cap. False when it is full.
  def begin_call!
    self.class.where(id: id).where("calls_running < ?", MAX_CALLS_AT_ONCE)
        .update_all([ "calls_running = calls_running + 1, updated_at = ?", Time.current ]) == 1
  end

  def end_call!
    self.class.where(id: id).where("calls_running > 0").update_all([ "calls_running = calls_running - 1, updated_at = ?", Time.current ])
  end

  # A web lookup the coding agent makes, through the gateway as Halon's agent so the ledger holds it under this
  # workspace. Returns what the block returns.
  def look_up_web!(params, &)
    AbilityGateway.authorize!(principal: SystemAgent.investigator, action_key: Ability::Action::WEB_READ, workspace: workspace,
                              params: params, context: { source: AbilityGateway::SOURCE_CODE_AGENT,
                                                         triggered_by_label: "Coding agent for #{repository}" }, &)
  end

  # A coding agent looks a few things up for one change. More is something else spending Firefight's searches.
  MAX_WEB_LOOKUPS = 40
  TOO_MANY_LOOKUPS = "This code change has used its #{MAX_WEB_LOOKUPS} web lookups.".freeze

  # Claimed in SQL, so lookups at once cannot all slip past the cap. False when it is spent.
  def count_web_lookup!
    self.class.where(id: id).where("web_lookups < ?", MAX_WEB_LOOKUPS)
        .update_all([ "web_lookups = web_lookups + 1, updated_at = ?", Time.current ]) == 1
  end

  def close!
    self.class.where(id: id, closed_at: nil).update_all(closed_at: Time.current, updated_at: Time.current)
  end
end
