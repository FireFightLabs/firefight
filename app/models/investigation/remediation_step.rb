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
  def self.checked(workspace, asked, position:)
    kind = asked["kind"].to_s
    raise Investigation::RemediationPlan::Refused, "Step #{position} is a #{kind.inspect}, which is not one of #{KINDS.join(', ')}." unless KINDS.include?(kind)

    refuse(position, "has its depends_on as something other than a list of step numbers") unless asked["depends_on"].nil? || asked["depends_on"].is_a?(Array)
    step = new(position: position, kind: kind, description: asked["description"].to_s.strip, undo: asked["undo"].presence,
               depends_on: Array(asked["depends_on"]).map(&:to_i))
    case kind
    when KIND_PULL_REQUEST
      step.repository = asked["repository"].to_s.strip.presence || refuse(position, "names no repository. Give the repository the change goes in")
    when KIND_ACTION
      tool = runnable_tool(workspace, asked["tool"].to_s, position)
      refuse(position, "has its arguments as something other than an object") unless asked["arguments"].nil? || asked["arguments"].is_a?(Hash)
      step.assign_attributes(tool_name: asked["tool"], action_key: tool.action_key, arguments: asked["arguments"] || {})
    when KIND_MANUAL
      step.missing = asked["missing"].presence
    end
    refuse(position, "has no description. Say in a sentence what it changes") if step.description.empty?
    refuse(position, "holds what looks like a secret. Never put a credential in a fix") unless step.valid? || step.errors[:text].empty?
    step
  end

  def action? = kind == KIND_ACTION

  # Done by a person rather than run by Firefight. A code change joins them until Firefight can open the pull request.
  def by_hand? = !action?

  def proposed? = status == STATUS_PROPOSED

  def done? = status == STATUS_DONE

  def ended? = ENDED.include?(status)

  # The tool this step runs, while it is still switched on, offered and changes something.
  def tool_to_run(workspace = plan.finding.investigation.workspace)
    slug, name = action_key.to_s.split(".", 2)
    Integration::Tool.in_workspace(workspace).where(integrations: { slug: slug }, name: name, read_only: false).first
  end

  def ready?(siblings) = depends_on.all? { |position| siblings.find { |each| each.position == position }&.done? }

  def held_back?(siblings) = depends_on.any? { |position| STOPPED.include?(siblings.find { |each| each.position == position }&.status) }

  # A person's step goes in order like any other, so marking it done never lets a step run past one that has not gone
  # through.
  def mark_done_blocked_reason(siblings = plan.steps)
    return "Firefight runs step #{position} itself once the fix is applied." if action?
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

  # A tool's words are kept to be read, never a credential it handed back, which is redacted before it is stored.
  def finish!(status, result: nil, invocation_id: nil)
    move!(from: [ STATUS_RUNNING, STATUS_WAITING_APPROVAL ], to: status, result: self.class.redacted(result)&.truncate(RESULT_LIMIT),
          invocation_id: invocation_id || self.invocation_id, finished_at: Time.current)
  end

  def self.redacted(text)
    return if text.nil?

    IncidentTranscriptMessage::Scrubbing::SECRET_PATTERNS.reduce(text) { |kept, (name, pattern)| kept.gsub(pattern, "[REDACTED:#{name}]") }
  end

  def stale? = status == STATUS_RUNNING && started_at.present? && started_at < STALE_AFTER.ago

  # Everything the agent wrote into the step, which the secret check reads, since a fix is shown and kept.
  def text = [ description, repository, missing, undo, arguments.to_json ].compact.join(" ")

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
