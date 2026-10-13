# Asks named people, or anyone holding a workspace role, to approve before the run goes on. It is an approval like any
# the gateway asks for (Ability::Approval), so it is decided on the Approvals page and the run's page as any is. It is
# asked in the incident's channel, else the channel of the team that owns the workflow, and by direct message only of
# the people it names, who may decide it without approvals access. Approved takes the approved route and denied the
# denied route. When it names an incident, its conditions are read again about once every few minutes while it waits
# and once more when it is approved, and a request whose incident no longer meets them, or that nobody decided within
# the step's wait, is withdrawn, saying why where it was asked, and takes the withdrawn route. It changes nothing itself.
class DefinedWorkflow::Steps::Approval < DefinedWorkflow::Steps::Base
  include DefinedWorkflow::Steps::Waiting

  kind "approval"
  label "Approval"
  group GROUP_PEOPLE

  KEY_QUESTION = "question".freeze
  KEY_DETAILS = "details".freeze
  KEY_WHO = "who".freeze
  KEY_APPROVERS = "approvers".freeze
  KEY_ROLE = "role".freeze
  KEY_INCIDENT = "incident".freeze
  KEY_CONDITIONS = "conditions".freeze
  WHO_PEOPLE = "people".freeze
  WHO_ROLE = "role".freeze
  WHO = [ WHO_PEOPLE, WHO_ROLE ].freeze
  ROLES = [ WorkspaceMembership.roles[:admin], WorkspaceMembership.roles[:owner] ].freeze
  ROUTE_APPROVED = "approved".freeze
  ROUTE_DENIED = "denied".freeze
  ROUTE_WITHDRAWN = "withdrawn".freeze
  ROUTES = [ ROUTE_APPROVED, ROUTE_DENIED, ROUTE_WITHDRAWN ].freeze
  OUTPUT_DECISION = "decision".freeze
  OUTPUT_DECIDED_BY = "decided_by".freeze
  OUTPUT_REASON = "reason".freeze
  APPROVER_LIMIT = 10
  QUESTION_LIMIT = 1_000
  CONDITION_LIMIT = Workflow::Trigger::CONDITION_LIMIT
  # How often the incident's conditions are read again while it waits.
  RECHECK = 5.minutes
  CHECKPOINT_HELD = DefinedWorkflow::Steps::CallTool::CHECKPOINT_HELD
  DECIDED = DefinedWorkflow::Steps::CallTool::APPROVAL

  config_help "question (what approvers decide, may use references), details (optional, may use references), who (#{WHO.join(' or ')}), " \
              "approvers (up to #{APPROVER_LIMIT} emails, for people), role (#{ROLES.join(' or ')}, for role), incident (optional, its " \
              "identifier), conditions (optional, [{field, operator, value}] on that incident as incident_declared's are, read again while " \
              "it waits and when approved), #{wait_help}. It is asked in the incident's channel, else the owning team's, and by direct " \
              "message of the people it names. Takes approved, denied, or withdrawn when nobody decided within its wait or the " \
              "incident no longer meets the conditions. Outputs decision, decided_by and reason."

  class << self
    def output_fields(_config) = [ OUTPUT_DECISION, OUTPUT_DECIDED_BY, OUTPUT_REASON ]

    def approver_emails(config) = Array(config[KEY_APPROVERS]).map { |email| email.to_s.strip }.compact_blank.uniq

    def problems(step, _workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      found = []
      found << "#{named} needs the question approvers decide." if config[KEY_QUESTION].to_s.strip.empty?
      found << "#{named} asks in at most #{QUESTION_LIMIT.to_fs(:delimited)} characters." if config[KEY_QUESTION].to_s.length > QUESTION_LIMIT
      found.concat(who_problems(config, named))
      found.concat(wait_problems(config, named))
      found.concat(condition_problems(config, named))
    end

    def who_problems(config, named)
      case config[KEY_WHO]
      when WHO_PEOPLE
        emails = approver_emails(config)
        return [ "#{named} needs the people who approve, by email." ] if emails.empty?
        return [ "#{named} names at most #{APPROVER_LIMIT} approvers." ] if emails.size > APPROVER_LIMIT
      when WHO_ROLE
        return [ "#{named} needs the role that approves, #{ROLES.join(' or ')}." ] unless ROLES.include?(config[KEY_ROLE].to_s)
      else
        return [ "#{named} needs who approves, named people or a role." ]
      end
      []
    end

    def condition_problems(config, named)
      given = config[KEY_CONDITIONS]
      return [] if given.blank?
      return [ "#{named} needs its conditions as a list." ] unless given.is_a?(Array)
      return [ "#{named} holds at most #{CONDITION_LIMIT} conditions." ] if given.size > CONDITION_LIMIT
      return [ "#{named} needs the incident its conditions read." ] if config[KEY_INCIDENT].to_s.strip.empty?

      Policy::Conditions.errors_for(given).map { |message| "#{named}'s #{message.downcase_first}." }
    end

    def describe(config, _workspace)
      who = config[KEY_WHO] == WHO_ROLE ? "a workspace #{config[KEY_ROLE]}" : approver_emails(config).to_sentence
      "#{who} decides: #{config[KEY_QUESTION].to_s.squish}".truncate(200)
    end
  end

  def perform
    held = @step.checkpoint.to_h[CHECKPOINT_HELD]
    held ? waited(held) : ask
  end

  private

  def ask
    stale = stale_reason
    return withdrawn(stale) if stale

    approval = Ability::Approval.create!(
      workspace: workspace, principal_type: principal.class.polymorphic_name, principal_id: principal.id, principal_label: principal.principal_label,
      action_key: Ability::Action::WORKFLOW_APPROVAL, request_digest: Ability::Approval.digest(Ability::Action::WORKFLOW_APPROVAL, asked, {}),
      params: asked, scope: {}, required_role: required_role, approver_ids: Ability::Principal.references(approvers.map(&:id)), incident_id: incident&.id,
      workflow_run: @run, source: AbilityGateway::SOURCE_WORKFLOW, notify: notify
    )
    ApprovalResumption.park_workflow_step!(approval, @step.id, @step.name)
    SolidWorkflow::Step.where(id: @step.id).update_all([ "checkpoint = COALESCE(checkpoint, '{}'::jsonb) || jsonb_build_object(?::text, ?::text)", CHECKPOINT_HELD, approval.id ])
    ActiveRecord.after_all_transactions_commit { AbilityApprovalNotificationJob.perform_later(approval_id: approval.id) }
    park
  end

  def waited(approval_id)
    approval = Ability::Approval.find_by(id: approval_id)
    raise Refused, "The approval this step waited for is gone." unless approval

    decided = @step.checkpoint.to_h.dig(CHECKPOINT_DELIVERED, "#{DECIDED}:#{approval.id}")
    return decision(approval) if decided || !approval.pending?

    stale = deadline <= Time.current ? "Nobody decided within #{wait_words}." : stale_reason
    return withdraw(approval, stale) if stale

    park
  end

  def decision(approval)
    by = approval.approver&.actor_display_name
    return withdrawn(approval.withdrawn_reason || "It was withdrawn before anyone decided.") unless approval.approved? || approval.denied?
    return routed(ROUTE_DENIED, by, nil) if approval.denied?

    stale = stale_reason
    return withdrawn("#{by || 'An approver'} approved it, but by then #{stale}") if stale

    routed(ROUTE_APPROVED, by, nil)
  end

  def withdraw(approval, reason)
    approval.expire!(reason: reason)
    withdrawn(reason)
  end

  def withdrawn(reason) = routed(ROUTE_WITHDRAWN, nil, reason)

  def routed(route, by, reason)
    SolidWorkflow::Routed.new(output: { OUTPUT_DECISION => route, OUTPUT_DECIDED_BY => by, OUTPUT_REASON => reason }, route: route)
  end

  # Wakes to read the incident again while it waits, and at the end of its time limit.
  def park
    wake = conditions.any? ? [ deadline, RECHECK.from_now ].min : deadline
    SolidWorkflow::Park.new(wake_at: wake)
  end

  def deadline = (@step.first_started_at || Time.current) + handed_off_limit

  # Why the request no longer stands, in a sentence, or nil while the incident still meets its conditions.
  def stale_reason
    return if conditions.empty?
    return "#{@config[KEY_INCIDENT]} is not an incident." unless incident
    return if Policy::Conditions.all?(conditions, Workflow::TriggerPayloads.new(workspace).incident_context(incident.reload))

    "#{incident.identifier} no longer meets its conditions."
  end

  def conditions = Array(@config[KEY_CONDITIONS])

  def incident
    return @incident if defined?(@incident)

    @incident = DefinedWorkflow::Steps::People.incident(workspace, @config)
  end

  def asked
    { "question" => @config[KEY_QUESTION].to_s.strip, "details" => @config[KEY_DETAILS].to_s.strip.presence, "workflow" => @run.workflow.name,
      "run_id" => @run.id, "run_step_id" => record&.id, "step" => @step.name }.compact
  end

  def required_role = @config[KEY_WHO] == WHO_ROLE ? @config[KEY_ROLE].to_s : WorkspaceMembership.roles[:admin]

  # Asked in a channel always, and by direct message only of the people it names, never everyone holding a role.
  def notify = @config[KEY_WHO] == WHO_PEOPLE ? PolicyRule::ApprovalOutcome::NOTIFY_BOTH : PolicyRule::ApprovalOutcome::NOTIFY_CHANNEL

  def approvers
    return [] unless @config[KEY_WHO] == WHO_PEOPLE

    self.class.approver_emails(@config).map do |email|
      workspace.workspace_memberships.resolve(email, acting: principal) || raise(Refused, "No member is #{email}, so nobody was asked.")
    end
  end
end
