# What lets one coding agent in the sandbox reach a model for one code change, through Firefight's model proxy. The
# token is the only credential the box ever holds. It reaches one model, until a budget is spent or the session ends,
# and Firefight's own provider key never leaves Firefight. It fetches through the git gate but never pushes. A push
# signs in with a token of its own, made for Firefight's push of the reviewed change and good only while that push runs.
class CodeAgentSession < ApplicationRecord
  include CodeAgentSession::PullRequest

  # The key of a box opened for a session that no run holds.
  CODE_BOX_PREFIX = "code-agent-".freeze
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
  # Whoever asked for the change. The agent reads connected systems as them and asks them its questions.
  belongs_to :principal, polymorphic: true, optional: true
  # Where the change was asked for, a chat or a fix's step, where its questions are shown.
  belongs_to :place, polymorphic: true, optional: true
  has_many :questions, -> { order(:created_at, :id) }, class_name: "CodeAgentQuestion", dependent: :delete_all, inverse_of: :session
  # The steps the agent asked permission for, each decided by Halon or the person.
  has_many :permissions, -> { order(:created_at, :id) }, class_name: "CodeAgentPermission", dependent: :delete_all, inverse_of: :session
  has_many :pauses, -> { order(:created_at, :id) }, class_name: "CodeAgentSession::Pause", foreign_key: :session_id, dependent: :delete_all,
                    inverse_of: :session

  scope :live, -> { where(closed_at: nil).where("expires_at > ?", Time.current) }
  # Still being written, so an answer to its agent's question can still change: live and not being pushed.
  scope :running, -> { live.where("push_open_until IS NULL OR push_open_until <= ?", Time.current) }

  # The session and the token the box sends, which is shown once and kept only as a digest.
  # request is the CodeAgent::Request the change was asked with, nil for a change nobody asked for in person.
  # box_key names the box the run reads code in, which the agent's reads share. A coding agent asks the model many times
  # on one change, so the budget covers the change, not a call, and is the workspace's unless one is given.
  def self.open!(workspace:, choice:, repository:, request: nil, box_key: nil, budget_micros: nil)
    token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    payer = choice.payer || AiPayer.deployment(workspace)
    session = create!(workspace: workspace, provider: choice.provider_name, model: choice.model, repository: repository,
                      budget_micros: budget_micros || workspace.code_fix_budget_micros, expires_at: LIFETIME.from_now, token_digest: digest(token),
                      paid_by: payer.paid_by, workspace_ai_account: payer.account, principal: request&.principal,
                      place: request&.place, tool_call_id: request&.tool_call_id, box_key: box_key || request&.box_key)
    [ session, token ]
  end

  def self.authenticate(token)
    return if token.blank?

    live.find_by(token_digest: digest(token))
  end

  # The session whose push is open now, for the push token Firefight handed its own push. The agent's lifetime does not
  # bound it, so a push after a long review still goes through.
  def self.authenticate_push(token)
    return if token.blank?

    where(closed_at: nil).where("push_open_until > ?", Time.current).find_by(push_token_digest: digest(token))
  end

  def self.digest(token) = OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)

  def over_budget? = spent_micros >= budget_micros

  # "$2", or "$2.50" when there are cents.
  def self.dollars(micros)
    cents = micros / FirefightAi::AgentLoop::MICROS_PER_CENT
    (cents % 100).zero? ? "$#{cents / 100}" : format("$%.2f", cents / 100.0)
  end

  # A provider refusing the key itself, rather than the request.
  KEY_REFUSED_STATUSES = [ 401, 403 ].freeze
  ACCOUNT_GONE = "The AI account paying for this code change was removed.".freeze

  def payer = AiPayer.new(paid_by: paid_by || AiPayer.deployment(workspace).paid_by, account: workspace_ai_account)

  # The deployment's own keys refused one of the agent's calls for credit, which people hear only as AiCredit says it.
  def house_refused_for_credit?
    !payer.own_account? && Inference.where(inferable: self, error_kind: Inference::ERROR_OUT_OF_CREDIT).exists?
  end

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
                                                         triggered_by_label: triggered_by_label }, &)
  end

  # A service the coding agent starts in its sandbox, through the gateway as Halon's agent so the ledger holds it under
  # this workspace. Returns what the block returns.
  def start_sandbox_service!(name, &)
    AbilityGateway.authorize!(principal: SystemAgent.investigator, action_key: Ability::Action::SANDBOX_SERVICE, workspace: workspace,
                              params: { "name" => name }, context: { source: AbilityGateway::SOURCE_CODE_AGENT,
                                                                     triggered_by_label: triggered_by_label }, &)
  end

  # A coding agent looks a few things up for one change. More is something else spending Firefight's searches.
  MAX_WEB_LOOKUPS = 40
  TOO_MANY_LOOKUPS = "This code change has used its #{MAX_WEB_LOOKUPS} web lookups.".freeze

  # Claimed in SQL, so lookups at once cannot all slip past the cap. False when it is spent.
  def count_web_lookup!
    self.class.where(id: id).where("web_lookups < ?", MAX_WEB_LOOKUPS)
        .update_all([ "web_lookups = web_lookups + 1, updated_at = ?", Time.current ]) == 1
  end

  # What the agent reads of connected systems for one change. More is something else spending the asker's reach.
  MAX_TOOL_CALLS = 80
  TOO_MANY_TOOL_CALLS = "This code change has used its #{MAX_TOOL_CALLS} tool calls.".freeze

  # Claimed in SQL, so calls at once cannot all slip past the cap. False when it is spent.
  def count_tool_call!
    self.class.where(id: id).where("tool_calls < ?", MAX_TOOL_CALLS)
        .update_all([ "tool_calls = tool_calls + 1, updated_at = ?", Time.current ]) == 1
  end

  # Claimed in SQL, so questions asked at once cannot pass the cap. False when the change asked all it may.
  def count_question!
    self.class.where(id: id).where("questions_asked < ?", CodeAgentQuestion::MAX_PER_CHANGE)
        .update_all([ "questions_asked = questions_asked + 1, updated_at = ?", Time.current ]) == 1
  end

  # A question the database refused gives its place back.
  def uncount_question!
    self.class.where(id: id).where("questions_asked > 0").update_all([ "questions_asked = questions_asked - 1, updated_at = ?", Time.current ])
  end

  # What the change's tool calls are logged as in Activity.
  def triggered_by_label = "Coding agent for #{repository}"

  # Opens the gate to one push for this long, and answers the token that push signs in with, or nil once the session
  # closed. Opening again replaces the token, so only the newest push gets through.
  def open_push!(within)
    token = SecureRandom.urlsafe_base64(TOKEN_BYTES)
    opened = self.class.where(id: id, closed_at: nil)
                 .update_all(push_token_digest: self.class.digest(token), push_open_until: within.from_now, updated_at: Time.current) == 1
    token if opened
  end

  def close_push!
    self.class.where(id: id).update_all(push_token_digest: nil, push_open_until: nil, updated_at: Time.current)
  end

  def pushing? = push_open_until.present? && push_open_until.future?

  def running? = closed_at.nil? && expires_at.future? && !pushing?

  def time_left = [ expires_at - Time.current, 0 ].max

  def open_question = questions.from_agent.find_by(status: CodeAgentQuestion::STATUS_OPEN)

  # Why the agent's model call is refused, or nil. A step OpenCode asked about holds its session until Firefight answers,
  # so a call from that session while the question is open means something in the box answered it instead, and one
  # answered in the box ends the whole run. agent_session is OpenCode's own session that calls.
  def model_call_refusal!(agent_session)
    if agent_session.present?
      permissions.where(status: CodeAgentPermission::STATUS_OPEN, agent_session_id: agent_session.to_s).find_each(&:answered_in_box!)
    end
    CodeAgentPermission::ANSWERED_IN_BOX if permissions.answered_in_box.exists?
  end

  # A question nobody answered in time with nothing to fall back on ends the change, whatever the agent did after. One
  # with a recommendation went with it.
  def unanswered_question = questions.from_agent.find_by(status: CodeAgentQuestion::STATUS_EXPIRED)

  def close!
    self.class.where(id: id, closed_at: nil).update_all(closed_at: Time.current, push_token_digest: nil, push_open_until: nil, updated_at: Time.current)
  end

  # What the change's model calls spent, by feature (the writing, its reviews, the questions Halon answered for it):
  # how many calls, the tokens read and written, and the cost, as the ledger holds them.
  def spend
    Inference.where(inferable: self).group(:feature)
             .pluck(:feature, Arel.sql("COUNT(*)"), Arel.sql("SUM(input_tokens)"), Arel.sql("SUM(cache_read_tokens)"), Arel.sql("SUM(cache_write_tokens)"),
                    Arel.sql("SUM(output_tokens)"), Arel.sql("SUM(cost_micros)"))
             .to_h do |feature, calls, input, cache_read, cache_write, output, cost|
               [ feature, { calls: calls, input_tokens: input.to_i, cache_read_tokens: cache_read.to_i, cache_write_tokens: cache_write.to_i,
                            output_tokens: output.to_i, cost_micros: cost.to_i } ]
             end
  end

  # How many of the oldest tool results each of the agent's conversations has cleared, by the conversation's key, so
  # every call of a conversation clears the same ones until its next batch (FirefightAi::ModelProxy::History).
  def cleared_through = tool_result_clearing.fetch(CLEARED_THROUGH, {})

  # Whether the provider may still be asked to clear old tool results itself. One that refused a request for asking is
  # not asked again in this session.
  def provider_clears? = !tool_result_clearing[PROVIDER_REFUSED]

  # Keeps what a call cleared, in SQL. A count only ever grows, so of two calls at once the larger stands.
  def cleared!(trim)
    return unless trim

    if trim.provider_refused
      self.class.where(id: id).update_all([ "tool_result_clearing = jsonb_set(tool_result_clearing, ?, 'true'::jsonb), updated_at = ?", "{#{PROVIDER_REFUSED}}",
                                            Time.current ])
    end
    return unless trim.count.positive?

    self.class.where(id: id).update_all([ <<~SQL.squish, CLEARED_THROUGH, CLEARED_THROUGH, trim.conversation, CLEARED_THROUGH, trim.conversation, trim.count, Time.current ])
      tool_result_clearing = jsonb_set(tool_result_clearing, ARRAY[?],
        COALESCE(tool_result_clearing -> ?, '{}'::jsonb) || jsonb_build_object(?::text,
          GREATEST(COALESCE((tool_result_clearing -> ? ->> ?)::integer, 0), ?))), updated_at = ?
    SQL
  end

  CLEARED_THROUGH = "through".freeze
  PROVIDER_REFUSED = "providerRefused".freeze
  private_constant :CLEARED_THROUGH, :PROVIDER_REFUSED
end
