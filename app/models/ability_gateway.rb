# The chokepoint every privileged operation routes through: resolve the
# principal's grants, decide, ledger, execute. Convergence here IS the
# safety property — API controllers, MCP dispatch, and (later) agent tool
# calls all pass through this one method.
#
# Ledger policy: denials are always recorded, and so is every allowed call
# that either changes something or reaches another system, as a write-ahead
# row finalized after the call. Reads of Firefight's own data are left out;
# they run at request volume and the request log already covers them.
class AbilityGateway
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
  # denial) when no grant covers the action, or PendingApproval when an
  # approval policy matches and no usable approval accompanies the call
  # (pass context[:approval_id] on the retry after it is approved).
  def self.authorize!(principal:, action_key:, workspace:, scope: {}, params: {}, context: {})
    action = Ability::Action.lookup(action_key, workspace)

    unless permitted?(principal, action, action_key, scope) && action&.configured_for?(scope)
      record!(decision: Ability::Invocation::DECISION_DENY, completed_at: Time.current,
              principal: principal, action: action, action_key: action_key,
              workspace: workspace, scope: scope, params: params, context: context)
      raise Denied.new(action_key)
    end

    approval = approval_gate!(principal: principal, action: action, action_key: action_key,
                              workspace: workspace, scope: scope, params: params, context: context)

    invocation = nil
    if ledger_execution?(action)
      invocation = record!(decision: Ability::Invocation::DECISION_ALLOW, completed_at: nil,
                           principal: principal, action: action, action_key: action_key,
                           workspace: workspace, scope: scope, params: params, context: context,
                           approval: approval)
    end
    approval&.consume!

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

  # Returns the usable approval when one is required and supplied, nil when
  # no policy matches. Raises PendingApproval (creating or re-surfacing the
  # pending record) or Denied (the supplied approval was denied).
  def self.approval_gate!(principal:, action:, action_key:, workspace:, scope:, params:, context:)
    requirement = approval_requirement(workspace, action, action_key, scope, context)
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
      required_role: requirement["role"],
      self_approvable: requirement.fetch("self_approval", true),
      incident_id: context[:incident_id]
    )
    record!(decision: Ability::Invocation::DECISION_PENDING, completed_at: Time.current,
            principal: principal, action: action, action_key: action_key,
            workspace: workspace, scope: scope, params: params, context: context, approval: approval)
    raise PendingApproval.new(approval)
  end

  def self.approval_requirement(workspace, action, action_key, scope, context)
    # Resolving an approval is itself the approval mechanism — matching it
    # against approval policies would gate approvals behind approvals. The
    # Approval model's role/self-approval rules govern resolution instead.
    return nil if action_key.start_with?("#{ApiKey::RESOURCE_APPROVALS}.")

    policy = workspace.policies.enabled.for_domain(Policy::DOMAIN_APPROVALS)
                      .workspace_wide.order(:created_at).first
    return nil unless policy

    result = policy.evaluate(
      action_key: action_key,
      risk_level: action.risk_level,
      reversible: action.reversible,
      environment: scope["environment"] || scope[:environment],
      severity: context[:severity]
    )
    result.outcome&.dig(PolicyRule::ApprovalOutcome::REQUIRE_KEY)
  end

  # Anything that leaves Firefight is recorded, reads included: "what did an
  # agent touch in our systems" is the question the ledger exists to answer.
  # Reads of our own data are not, since they run at request volume and the
  # request log already covers them.
  def self.ledger_execution?(action)
    action.kind == Ability::Action::KIND_TOOL || action.risk_level != Ability::Action::RISK_READ
  end

  def self.record!(decision:, completed_at:, principal:, action:, action_key:, workspace:, scope:, params:, context:, approval: nil)
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
      approval_id: approval&.id,
      completed_at: completed_at
    )
  end
end
