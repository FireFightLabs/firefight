# Denials are always ledgered. Allowed calls that change something or reach another
# system are ledgered as a write-ahead row finalized after the call.
class AbilityGateway
  SOURCE_API = "api"
  SOURCE_MCP = "mcp"
  SOURCE_SLACK = "slack"
  SOURCE_WEB = "web"
  # Firefight's own work rather than a person's click, so the ledger names the origin.
  SOURCE_INVESTIGATION = "investigation"
  SOURCE_CONVERSATION = "conversation"
  # The resource map's sweep, calling a connection's tools with Firefight's own fixed reads.
  SOURCE_MAP_SWEEP = "map_sweep"
  # The health check, calling a connection's tools to see that it reaches the account behind its server.
  SOURCE_HEALTH_CHECK = "health_check"
  # A coding agent in the sandbox, writing a fix's code change.
  SOURCE_CODE_AGENT = "code_agent"
  # Keeping an item and its issue in a tracker in step, either way.
  SOURCE_ISSUE_SYNC = "issue_sync"
  # A watch Halon was asked to keep, reading as the person who asked until what it follows is done.
  SOURCE_WATCH = "watch"
  SOURCES = [ SOURCE_API, SOURCE_MCP, SOURCE_SLACK, SOURCE_WEB, SOURCE_INVESTIGATION, SOURCE_CONVERSATION, SOURCE_MAP_SWEEP,
              SOURCE_HEALTH_CHECK, SOURCE_CODE_AGENT, SOURCE_ISSUE_SYNC, SOURCE_WATCH ].freeze
  # Where a human acts directly rather than through a key or an agent.
  HUMAN_SOURCES = [ SOURCE_SLACK, SOURCE_WEB ].freeze

  class Denied < StandardError
    attr_reader :action_key

    def initialize(action_key)
      @action_key = action_key
      super("Not permitted to perform '#{action_key}'")
    end
  end

  class PendingApproval < StandardError
    attr_reader :approval

    def initialize(approval)
      @approval = approval
      super("'#{approval.action_key}' requires approval (approval id: #{approval.id})")
    end
  end

  # For callers that finalize after their own execution, such as the API's
  # around_action. No-ops when nothing was ledgered.
  class Authorization
    def initialize(invocation)
      @invocation = invocation
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # The step that ran the tool stores this as its receipt.
    def invocation_id
      @invocation&.id
    end

    def finalize_success!
      finalize(Ability::Invocation::OUTCOME_SUCCESS, nil)
    end

    def finalize_error!(error)
      finalize(Ability::Invocation::OUTCOME_ERROR, error.class.name)
    end

    # A call that ran but whose answer says it failed, such as a provider's own error or one of Firefight's tools
    # refusing, is ledgered as an error with the first line of what it said.
    def answer_failed!(text)
      @answer_failure = Ability::Invocation.summary_of(text)
    end

    def answer_failed? = !@answer_failure.nil?

    # A call one of Firefight's own rules refused after the gateway allowed it, such as a push to a protected branch, is
    # ledgered as refused with the first line of the rule's reason, since nothing failed.
    def answer_refused!(text)
      @answer_refusal = Ability::Invocation.summary_of(text)
    end

    # Once the call has answered, a success unless its answer said it failed or was refused.
    def finalize_answered!
      return finalize(Ability::Invocation::OUTCOME_REFUSED, @answer_refusal) if @answer_refusal
      return finalize_success! unless answer_failed?

      finalize(Ability::Invocation::OUTCOME_ERROR, @answer_failure)
    end

    private

    def finalize(outcome, error_summary)
      return unless @invocation

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round
      @invocation.finalize!(outcome: outcome, error_summary: error_summary, duration_ms: duration_ms)
    end
  end

  # Without a block, returns an Authorization the caller must finalize. With one, the block is handed it, so an answer
  # that says it failed can be ledgered as one. On PendingApproval, the retry passes context[:approval_id] once approved.
  # holdable: false is for a way in nothing could resume after an approval, or a search that only reads Firefight's own
  # data, which is ledgered but never held.
  def self.authorize!(principal:, action_key:, workspace:, scope: {}, params: {}, context: {}, holdable: true)
    action = Ability::Action.lookup(action_key, workspace)

    unless permitted?(principal, action, action_key, workspace, scope, params: params) && action&.configured_for?(scope)
      record!(decision: Ability::Invocation::DECISION_DENY, completed_at: Time.current,
              principal: principal, action: action, action_key: action_key,
              workspace: workspace, scope: scope, params: params, context: context)
      raise Denied.new(action_key)
    end

    approval = holdable ? approval_gate!(principal: principal, action: action, action_key: action_key,
                                         workspace: workspace, scope: scope, params: params, context: context) : nil

    invocation = nil
    claimed = true
    # One transaction, so a retry that loses the race for the approval rolls
    # its allow row back and is ledgered as a denial.
    Ability::Invocation.transaction do
      if ledger_execution?(action, principal, context)
        invocation = record!(decision: Ability::Invocation::DECISION_ALLOW, completed_at: nil,
                             principal: principal, action: action, action_key: action_key,
                             workspace: workspace, scope: scope, params: params, context: context,
                             approval: approval)
      end

      if approval && !approval.claim
        claimed = false
        raise ActiveRecord::Rollback
      end
    end

    unless claimed
      record!(decision: Ability::Invocation::DECISION_DENY, completed_at: Time.current,
              principal: principal, action: action, action_key: action_key,
              workspace: workspace, scope: scope, params: params, context: context,
              approval: approval)
      raise Denied.new(action_key)
    end

    authorization = Authorization.new(invocation)
    return authorization unless block_given?

    begin
      result = yield authorization
      authorization.finalize_answered!
      result
    rescue => error
      authorization.finalize_error!(error)
      raise
    end
  end

  # Asks for a fresh approval of a call without ever running it, as when an approved call expired before anyone ran it.
  # Raises Denied when the principal may no longer make the call and PendingApproval with the new request. Returns nil
  # when no rule holds the call any more, so the caller says so rather than running it.
  def self.request_approval!(principal:, action_key:, workspace:, scope: {}, params: {}, context: {})
    action = Ability::Action.lookup(action_key, workspace)
    raise Denied.new(action_key) unless permitted?(principal, action, action_key, workspace, scope, params: params) && action&.configured_for?(scope)
    return nil unless approval_requirement(workspace, action, action_key, scope, context, params: params)

    approval_gate!(principal: principal, action: action, action_key: action_key, workspace: workspace, scope: scope, params: params,
                   context: context.except(:approval_id))
  end

  # params is the call itself, which matters only for a tool that both reads and changes. A call it shows to read is a
  # read of its connection, held by default like any read and granted with the connection's read pack.
  def self.permitted?(principal, action, action_key, workspace, scope, params: nil)
    return false unless action
    return true if Ability::Action.open?(action_key)
    return true if principal.implicitly_allowed?(action)

    resolved = Ability::Resolver.resolve(principal, workspace)
    return !resolved.reach(action_key).nil? if Ability::Action.filtered?(action_key) && scope.blank?
    return true if resolved.covers?(action_key, scope)

    action.read_through_guard?(params) && reads_connection?(principal, action, resolved, scope)
  end

  def self.reads_connection?(principal, action, resolved, scope)
    principal.implicitly_allowed?(action, resolved, reads: true) ||
      resolved.covers?(Ability::Role.reads_key(action.source.integration_id), scope)
  end
  private_class_method :reads_connection?

  # Where a principal may read something filtered by environment (Ability::Action::FILTERED_KEYS), as a scope: {} for
  # every environment, { "environment" => catalog entry ids } for those alone, or nil for none. A reader filters its rows
  # by it, after the call itself was authorized.
  def self.reach(principal:, action_key:, workspace:)
    action = principal && Ability::Action.lookup(action_key, workspace)
    return nil unless action
    return {} if principal.implicitly_allowed?(action)

    Ability::Resolver.resolve(principal, workspace).reach(action_key)
  end

  # The caller claims the returned approval together with the allow ledger row.
  def self.approval_gate!(principal:, action:, action_key:, workspace:, scope:, params:, context:)
    requirement = approval_requirement(workspace, action, action_key, scope, context, params: params)
    return nil unless requirement

    supplied = workspace.ability_approvals.find_by(id: context[:approval_id]) if context[:approval_id]
    if supplied && supplied.principal_type == principal.class.polymorphic_name && supplied.principal_id == principal.id &&
       supplied.matches_request?(action_key, params, scope)
      raise Denied.new(action_key) if supplied.denied?
      return supplied if supplied.usable?
      raise PendingApproval.new(supplied) if supplied.pending?
    end

    approval = Ability::Approval.create!(
      workspace: workspace,
      principal_type: principal.class.polymorphic_name,
      principal_id: principal.id,
      principal_label: principal.principal_label,
      action_key: action_key,
      request_digest: Ability::Approval.digest(action_key, params, scope),
      scope: scope,
      params: params,
      **Ability::Approval.requirement_attributes(requirement),
      incident_id: context[:incident_id],
      source: context[:source]
    )
    record!(decision: Ability::Invocation::DECISION_PENDING, completed_at: Time.current,
            principal: principal, action: action, action_key: action_key,
            workspace: workspace, scope: scope, params: params, context: context, approval: approval)
    # Approvers are told from here, not from a model callback that would fire
    # on any row write.
    ActiveRecord.after_all_transactions_commit do
      AbilityApprovalNotificationJob.perform_later(approval_id: approval.id)
    end
    raise PendingApproval.new(approval)
  end

  # A read never waits on an approval rule, so a call shown to read through a tool that can also change things is never
  # held, whatever rule names the tool. Every change keeps every rule.
  def self.approval_requirement(workspace, action, action_key, scope, context, params: nil)
    return nil if Ability::Action.approval_exempt?(action_key)
    return nil if action.read_through_guard?(params)

    policy = workspace.approval_policy
    return nil unless policy&.enabled?

    result = policy.evaluate(
      action_key: action_key,
      risk_level: action.risk_level,
      reversible: action.reversible,
      environment: scope["environment"] || scope[:environment],
      severity: context[:severity]
    )
    result.outcome&.dig(PolicyRule::ApprovalOutcome::REQUIRE_KEY)
  end

  # Anything that leaves Firefight is recorded, reads included. Reads of our own data are
  # covered by the request log, and a person's incident participation by record_change!.
  def self.ledger_execution?(action, principal, context)
    return true if action.kind == Ability::Action::KIND_TOOL || Ability::Action.open?(action.key)
    return false if incident_participation?(action, principal, context)

    action.risk_level != Ability::Action::RISK_READ
  end

  def self.incident_participation?(action, principal, context)
    HUMAN_SOURCES.include?(context[:source]) && principal.is_a?(WorkspaceMembership) &&
      WorkspaceMembership::PARTICIPATION.key?(Ability::Action.resource_of(action.key))
  end

  # A call Firefight makes on its own, which nobody asked for and so nothing authorizes, is still in the activity log.
  # It is recorded before the block runs and finalized with how long it took. failed reads the block's result and
  # answers the error summary of an answer that failed, or nil, and rescued words an error the block raised.
  def self.record_unattended!(principal:, action_key:, workspace:, params:, context:, failed: ->(_result) { nil }, rescued: ->(error) { error.class.name })
    invocation = record!(decision: Ability::Invocation::DECISION_ALLOW, completed_at: nil, principal: principal,
                         action: Ability::Action.lookup(action_key, workspace), action_key: action_key, workspace: workspace,
                         scope: {}, params: params, context: context)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    said = failed.call(result)
    invocation.finalize!(outcome: said ? Ability::Invocation::OUTCOME_ERROR : Ability::Invocation::OUTCOME_SUCCESS, error_summary: said,
                         duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
    result
  rescue StandardError => error
    invocation&.finalize!(outcome: Ability::Invocation::OUTCOME_ERROR, error_summary: rescued.call(error))
    raise
  end

  def self.record!(decision:, completed_at:, principal:, action:, action_key:, workspace:, scope:, params:, context:, approval: nil)
    Ability::Invocation.create!(
      workspace: workspace,
      principal_type: principal.class.polymorphic_name,
      principal_id: principal.id,
      principal_label: principal.principal_label,
      triggered_by_label: context[:triggered_by_label],
      action_key: action_key,
      risk_level: action&.risk_of(params),
      source: context[:source],
      scope: scope,
      params: params,
      decision: decision,
      idempotency_key: SecureRandom.uuid,
      incident_id: context[:incident_id],
      approval_id: approval&.id,
      completed_at: completed_at
    )
  end
end
