# One step of a fix. A pull request changes code in one repository. An action runs one of the workspace's integration
# tools with the arguments given. A manual step is for a person, and says what is missing for Firefight to do it.
# Firefight runs action steps once the fix is applied. A person marks the others done, which lets what waits on them go.
class Investigation::RemediationStep < ApplicationRecord
  include Chat::SecretFree

  self.table_name = "investigation_remediation_steps"

  KIND_PULL_REQUEST = "pull_request".freeze
  KIND_ACTION = "action".freeze
  KIND_MANUAL = "manual".freeze
  KINDS = [ KIND_PULL_REQUEST, KIND_ACTION, KIND_MANUAL ].freeze

  STATUS_PROPOSED = "proposed".freeze
  STATUS_RUNNING = "running".freeze
  STATUS_WAITING_APPROVAL = "waiting_approval".freeze
  STATUS_DONE = "done".freeze
  STATUS_FAILED = "failed".freeze
  STATUS_DECLINED = "declined".freeze
  STATUS_SKIPPED = "skipped".freeze
  STATUSES = [ STATUS_PROPOSED, STATUS_RUNNING, STATUS_WAITING_APPROVAL, STATUS_DONE, STATUS_FAILED, STATUS_DECLINED, STATUS_SKIPPED ].freeze
  ENDED = [ STATUS_DONE, STATUS_FAILED, STATUS_DECLINED, STATUS_SKIPPED ].freeze
  # What stops the steps that wait on it.
  STOPPED = [ STATUS_FAILED, STATUS_DECLINED, STATUS_SKIPPED ].freeze
  # What a tool said back, kept for people to read and capped, since it is another system's words.
  RESULT_LIMIT = 2_000
  # A step running longer than this lost its worker, since a tool call is capped well under it.
  STALE_AFTER = 15.minutes
  # A code change installs the repository's dependencies and runs a coding agent for up to 15 minutes before it opens.
  # A connected coding agent is followed for a shorter time than this, and stopped at its own limit.
  CODE_STALE_AFTER = 45.minutes
  STATUS_WORDS = {
    STATUS_PROPOSED => "not started", STATUS_RUNNING => "running", STATUS_WAITING_APPROVAL => "waiting for approval",
    STATUS_DONE => "done", STATUS_FAILED => "failed", STATUS_DECLINED => "declined", STATUS_SKIPPED => "skipped"
  }.freeze

  belongs_to :plan, class_name: "Investigation::RemediationPlan", optional: true
  belongs_to :invocation, class_name: "Ability::Invocation", optional: true
  belongs_to :approval, class_name: "Ability::Approval", optional: true
  belongs_to :done_by, class_name: "WorkspaceMembership", optional: true

  scope :in_workspace, ->(workspace) { joins(plan: { finding: :investigation }).where(investigations: { workspace_id: workspace.id }) }

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :description, presence: true

  # A step the agent proposed, checked against what the workspace can run, and not saved yet. An action names a tool
  # the way the agent sees it, and only a tool that is switched on and changes something is a fix.
  def self.checked(workspace, asked, position:, principal:)
    kind = asked["kind"].to_s
    raise Investigation::RemediationPlan::Refused, "Step #{position} is a #{kind.inspect}, which is not one of #{KINDS.join(', ')}." unless KINDS.include?(kind)

    refuse(position, "has its depends_on as something other than a list of step numbers") unless asked["depends_on"].nil? || asked["depends_on"].is_a?(Array)
    step = new(position: position, kind: kind, description: asked["description"].to_s.strip, undo: asked["undo"].presence,
               depends_on: Array(asked["depends_on"]).map(&:to_i))
    case kind
    when KIND_PULL_REQUEST
      step.repository = asked["repository"].to_s.strip.presence || refuse(position, "names no repository. Give the repository the change goes in")
    when KIND_ACTION
      refuse(position, "has its arguments as something other than an object") unless asked["arguments"].nil? || asked["arguments"].is_a?(Hash)
      tool, arguments = action_of(workspace, asked["tool"].to_s, asked["arguments"] || {}, position, principal)
      step.assign_attributes(tool_name: asked["tool"], action_key: tool.action_key, arguments: arguments)
    when KIND_MANUAL
      step.missing = asked["missing"].presence
    end
    refuse(position, "has no description. Say in a sentence what it changes") if step.description.empty?
    refuse(position, "holds what looks like a secret. Never put a credential in a fix") unless step.valid? || step.errors[:text].empty?
    step
  end

  def action? = kind == KIND_ACTION

  def pull_request? = kind == KIND_PULL_REQUEST

  # Run by Firefight rather than done by a person. That is every action, and a code change once the workspace can open
  # the pull request for its repository.
  def runs_itself?(workspace = plan.finding.investigation.workspace) = action? || (pull_request? && tool_to_run(workspace).present?)

  def proposed? = status == STATUS_PROPOSED

  def done? = status == STATUS_DONE

  def ended? = ENDED.include?(status)

  # The tool this step runs, while it is still switched on, offered and changes something. A code change is written
  # by the code host's coding tool on the connection that sees its repository.
  def tool_to_run(workspace = plan.finding.investigation.workspace)
    return code_tool(workspace) if pull_request?

    slug, name = action_key.to_s.split(".", 2)
    Integration::Tool.in_workspace(workspace).where(integrations: { slug: slug }, name: name, read_only: false).first
  end

  # What the coding agent is asked, from the run's finding and the rest of the fix, so each pull request says why it
  # exists and where it sits among the others.
  def code_arguments
    finding = plan.finding
    siblings = plan.steps.select(&:pull_request?)
    order = siblings.size > 1 ? "This is change #{siblings.index(self) + 1} of #{siblings.size} in the fix." : nil
    earlier = siblings.select { |each| each.position < position && each.done? }.filter_map(&:result)
    brief = [
      description, ("Why: #{finding.summary}" if finding.summary.present?),
      (finding.evidence_items.map { |item| "- #{item.claim}" }.join("\n").presence),
      ("How to tell it worked: #{plan.verify}" if plan.verify.present?)
    ].compact.join("\n\n")
    summary = [ description, ("Why: #{finding.summary}" if finding.summary.present?) ].compact.join("\n\n")
    { "repo" => repository, "title" => description, "brief" => brief, "summary" => summary,
      "context" => [ order, *earlier.map { |text| "Merge it after: #{text.lines.first.to_s.strip}" } ].compact.join("\n").presence }.compact
  end

  def ready?(siblings) = depends_on.all? { |position| siblings.find { |each| each.position == position }&.done? }

  def held_back?(siblings) = depends_on.any? { |position| STOPPED.include?(siblings.find { |each| each.position == position }&.status) }

  # A person's step goes in order like any other, so marking it done never lets a step run past one that has not gone
  # through.
  def mark_done_blocked_reason(siblings = plan.steps)
    return "Firefight runs step #{position} itself once the fix is applied." if action?
    return code_runs_itself_reason if pull_request? && runs_itself?
    return "Step #{position} is already #{STATUS_WORDS.fetch(status)}." unless proposed?
    return "Step #{position} waits on step #{depends_on.join(' and ')}, which #{depends_on.size == 1 ? 'is' : 'are'} not done yet." unless ready?(siblings)

    nil
  end

  # Moves the step on only from where it was, so two workers never run or finish it twice. False when it had moved.
  def move!(from:, to:, **columns)
    won = self.class.where(id: id, status: Array(from)).update_all(status: to, updated_at: Time.current, **columns)
    reload
    won == 1
  end

  # Starts the step only while its fix is still being applied, in the same statement, so a step never starts after the
  # fix was cancelled.
  def claim!(from:, **columns)
    applying = Investigation::RemediationPlan.where(status: Investigation::RemediationPlan::STATUS_APPLYING).select(:id)
    won = self.class.where(id: id, status: Array(from), plan_id: applying)
                    .update_all(status: STATUS_RUNNING, updated_at: Time.current, **columns)
    reload
    won == 1
  end

  # Asks the gateway whether whoever applied the fix may make this step's call, and ledgers it. The caller makes the call
  # and finalizes what this returns, so the step keeps its ledger row.
  def authorize_call!(tool, scope:, arguments:, approval_id: nil)
    investigation = plan.finding.investigation
    AbilityGateway.authorize!(
      principal: plan.approved_by, action_key: tool.action_key, workspace: investigation.workspace, scope: scope, params: arguments,
      context: { source: plan.applied_from, approval_id: approval_id, incident_id: investigation.incident&.id,
                 triggered_by_label: "Step #{position} of the fix from #{investigation.incident&.identifier || 'a Halon run'}" }.compact
    )
  end

  def mark_done!(by:) = move!(from: STATUS_PROPOSED, to: STATUS_DONE, done_by_id: by.id, finished_at: Time.current)

  # What a long running step has done so far, such as where its coding agent is working, shown while it runs. Only a
  # running step takes it, so a late report never overwrites how the step ended.
  def progress!(text)
    self.class.where(id: id, status: STATUS_RUNNING)
        .update_all(result: self.class.redacted(text)&.truncate(RESULT_LIMIT), updated_at: Time.current) == 1
  end

  # A tool's words are kept to be read, never a credential it handed back, which is redacted before it is stored.
  def finish!(status, result: nil, invocation_id: nil)
    move!(from: [ STATUS_RUNNING, STATUS_WAITING_APPROVAL ], to: status, result: self.class.redacted(result)&.truncate(RESULT_LIMIT),
          invocation_id: invocation_id || self.invocation_id, finished_at: Time.current)
  end

  def self.redacted(text)
    return if text.nil?

    IncidentTranscriptMessage::Scrubbing::SECRET_PATTERNS.reduce(text) { |kept, (name, pattern)| kept.gsub(pattern, "[REDACTED:#{name}]") }
  end

  def stale_after = pull_request? ? CODE_STALE_AFTER : STALE_AFTER

  def stale? = status == STATUS_RUNNING && started_at.present? && started_at < stale_after.ago

  # Everything the agent wrote into the step, which the secret check reads, since a fix is shown and kept.
  def text = [ description, repository, missing, undo, arguments.to_json ].compact.join(" ")

  # The coding agent the workspace chose, while its tool is switched on. Otherwise a code host's tool that writes a
  # change, on the connection whose sweep put the repository on the map. With one such connection, that one.
  def code_tool(workspace)
    return workspace.code_fix_agent_tool if workspace.code_fix_agent.present?

    writers = IntegrationProvider.code_hosts.to_h { |provider| [ provider.key, provider.code_fix_tool ] }
    tools = Integration::Tool.in_workspace(workspace).where(integrations: { provider: writers.keys }, read_only: false).to_a
                             .select { |tool| writers[tool.integration.provider] == tool.name }
    # A path two code hosts both hold, such as a mirror, is two repositories, so it is the code hosts' own that count.
    seen = ResourceMap::Resource.present.where(workspace: workspace, kind: ResourceMap::KIND_REPOSITORY, external_id: repository, provider: writers.keys)
                                .includes(:integration_environment).filter_map { |resource| resource.integration_environment&.integration_id }
    holders = tools.select { |tool| seen.include?(tool.integration_id) }
    holders.one? ? holders.first : (tools.first if tools.one?)
  end

  def code_runs_itself_reason
    agent = plan.finding.investigation.workspace.code_fix_agent_connection
    return "Firefight opens step #{position}'s pull request itself once the fix is applied." unless agent

    "Firefight hands step #{position}'s change to #{agent.name} once the fix is applied, and #{agent.name} opens the pull request."
  end

  # The provider tool a step runs and its own arguments. A capability, such as rollback, is resolved now to the
  # connection that holds the resource, so the step shows and runs exactly the provider call it will make.
  def self.action_of(workspace, name, arguments, position, principal)
    spec = Integrations::Capabilities::SPECS.values.find { |each| each.tool_name == name }
    return [ runnable_tool(workspace, name, position), arguments ] unless spec
    refuse(position, "names #{name}, which only reads. A fix has to change something") unless spec.writes

    call = Integrations::Capabilities.resolve(workspace, spec.key, arguments.transform_keys(&:to_s), principal: principal)
    environment = call.environment_entry&.slug
    [ runnable_tool(workspace, call.tool.model_facing_name, position),
      environment ? call.arguments.merge(Integration::Tool::ENVIRONMENT_ARG => environment) : call.arguments ]
  rescue Integrations::Capabilities::Unroutable => error
    refuse(position, "names #{name}, which cannot run here: #{error.message.delete_suffix('.')}. Make it a manual step and say so")
  end
  private_class_method :action_of

  def self.runnable_tool(workspace, name, position)
    tool = Integration::Tool.in_workspace(workspace).find { |each| each.model_facing_name == name }
    refuse(position, "names #{name.inspect}, which this workspace has not switched on. Make it a manual step and say what is missing") unless tool
    refuse(position, "names #{name}, which only reads. A fix has to change something") if tool.read_only
    unless tool.configured_for?({})
      refuse(position, "names #{name}, whose connection is not working or has no environment set up. Make it a manual step and say so")
    end
    tool
  end
  private_class_method :runnable_tool

  def self.refuse(position, reason)
    raise Investigation::RemediationPlan::Refused, "Step #{position} #{reason}."
  end
  private_class_method :refuse
end
