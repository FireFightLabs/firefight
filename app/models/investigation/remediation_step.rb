# One step of a fix. A pull request changes code in one repository. An action runs one of the workspace's integration
# tools with the arguments given. A manual step is for a person, and says what is missing for Firefight to do it.
class Investigation::RemediationStep < ApplicationRecord
  include Chat::SecretFree

  self.table_name = "investigation_remediation_steps"

  KIND_PULL_REQUEST = "pull_request".freeze
  KIND_ACTION = "action".freeze
  KIND_MANUAL = "manual".freeze
  KINDS = [ KIND_PULL_REQUEST, KIND_ACTION, KIND_MANUAL ].freeze

  STATUS_PROPOSED = "proposed".freeze
  STATUSES = [ STATUS_PROPOSED ].freeze

  belongs_to :plan, class_name: "Investigation::RemediationPlan", optional: true

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
