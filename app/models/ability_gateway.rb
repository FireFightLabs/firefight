# The chokepoint every privileged operation routes through: resolve the
# principal's grants, decide, ledger, execute. Convergence here IS the
# safety property — API controllers, MCP dispatch, and (later) agent tool
# calls all pass through this one method.
#
# Ledger policy: denials are always recorded; allowed write/destructive
# executions get a write-ahead row finalized after the call; allowed reads
# are not ledgered (request logs and OTel already cover them — tool-kind
# reads revisit this when Connections land).
class AbilityGateway
  class Denied < StandardError
    attr_reader :action_key

    def initialize(action_key)
      @action_key = action_key
      super("Not permitted to perform '#{action_key}'")
    end
  end

  # Handle returned to callers that finalize after their own execution
  # (e.g. the API layer's around_action). No-ops when nothing was ledgered.
  class Authorization
    def initialize(invocation)
      @invocation = invocation
      @started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def finalize_success!
      finalize(Ability::Invocation::OUTCOME_SUCCESS, nil)
    end

    def finalize_error!(error)
      finalize(Ability::Invocation::OUTCOME_ERROR, error.class.name)
    end

    private

    def finalize(outcome, error_summary)
      return unless @invocation

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started_at) * 1000).round
      @invocation.finalize!(outcome: outcome, error_summary: error_summary, duration_ms: duration_ms)
    end
  end

  # With a block: authorizes, executes the block, finalizes the ledger row,
  # returns the block's result. Without a block: returns an Authorization
  # handle the caller must finalize. Raises Denied (after ledgering the
  # denial) when no grant covers the action.
  def self.authorize!(principal:, action_key:, workspace:, scope: {}, params: {}, context: {})
    action = Ability::Action.lookup(action_key, workspace)

    unless permitted?(principal, action, action_key, scope)
      record!(decision: Ability::Invocation::DECISION_DENY, completed_at: Time.current,
              principal: principal, action: action, action_key: action_key,
              workspace: workspace, scope: scope, params: params, context: context)
      raise Denied.new(action_key)
    end

    invocation = nil
    if ledger_execution?(action)
      invocation = record!(decision: Ability::Invocation::DECISION_ALLOW, completed_at: nil,
                           principal: principal, action: action, action_key: action_key,
                           workspace: workspace, scope: scope, params: params, context: context)
    end

    authorization = Authorization.new(invocation)
    return authorization unless block_given?

    begin
      result = yield
      authorization.finalize_success!
      result
    rescue => error
      authorization.finalize_error!(error)
      raise
    end
  end

  def self.permitted?(principal, action, action_key, scope)
    return false unless action

    principal.implicitly_allowed?(action) ||
      Ability::Resolver.resolve(principal).covers?(action_key, scope)
  end

  def self.ledger_execution?(action)
    action.risk_level != Ability::Action::RISK_READ
  end

  def self.record!(decision:, completed_at:, principal:, action:, action_key:, workspace:, scope:, params:, context:)
    Ability::Invocation.create!(
      workspace: workspace,
      principal_type: principal.class.polymorphic_name,
      principal_id: principal.id,
      principal_label: principal.principal_label,
      triggered_by_label: context[:triggered_by_label],
      action_key: action_key,
      risk_level: action&.risk_level,
      scope: scope,
      params: params,
      decision: decision,
      idempotency_key: SecureRandom.uuid,
      incident_id: context[:incident_id],
      completed_at: completed_at
    )
  end
end
