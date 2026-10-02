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

  scope :live, -> { where(closed_at: nil).where("expires_at > ?", Time.current) }

  # The session and the token the box sends, which is shown once and kept only as a digest.
  def self.open!(workspace:, choice:, repository:, budget_micros: DEFAULT_BUDGET_MICROS)
    token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    session = create!(workspace: workspace, provider: choice.provider_name, model: choice.model, repository: repository,
                      budget_micros: budget_micros, expires_at: LIFETIME.from_now, token_digest: digest(token))
    [ session, token ]
  end

  def self.authenticate(token)
    return if token.blank?

    live.find_by(token_digest: digest(token))
  end

  def self.digest(token) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)

  def over_budget? = spent_micros >= budget_micros

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

  def close!
    self.class.where(id: id, closed_at: nil).update_all(closed_at: Time.current, updated_at: Time.current)
  end
end
