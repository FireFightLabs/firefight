# How to fix what a run found, written by the agent when it names a cause: ordered steps, how to tell it worked, and who
# approved it. Every finding with a cause has one, whether or not anything can apply it, since a fix nobody can run is
# still steps for a person. Applying it is a later decision, never part of writing it.
class Investigation::RemediationPlan < ApplicationRecord
  self.table_name = "investigation_remediation_plans"

  STATUS_PROPOSED = "proposed".freeze
  STATUSES = [ STATUS_PROPOSED ].freeze

  # Raised when a proposal cannot be recorded, with a reason the agent can act on.
  class Refused < StandardError; end

  # A proposal checked against what the workspace can run, and not saved yet.
  Checked = Data.define(:summary, :verify, :steps)

  belongs_to :finding, class_name: "Investigation::Finding"
  belongs_to :approved_by, class_name: "WorkspaceMembership", optional: true
  has_many :steps, -> { order(:position) }, class_name: "Investigation::RemediationStep", foreign_key: :plan_id, inverse_of: :plan,
                                             dependent: :destroy

  validates :summary, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Checks a proposal before anything is written, so a step naming a tool this workspace cannot run, or a code change
  # with no repository, is sent back with why. Cheap, so a run can call it before paying for anything else.
  def self.check!(workspace, fix)
    raise Refused, "The fix must be an object with a summary and steps." unless fix.is_a?(Hash)

    asked = fix.stringify_keys
    raise Refused, "A fix needs a summary saying what it changes." if asked["summary"].to_s.strip.empty?
    raise Refused, "A fix needs its steps as a list, at least one." unless asked["steps"].is_a?(Array) && asked["steps"].any?

    steps = asked["steps"].each_with_index.map do |step, index|
      raise Refused, "Step #{index + 1} must be an object." unless step.is_a?(Hash)

      Investigation::RemediationStep.checked(workspace, step.stringify_keys, position: index + 1)
    end
    order!(steps)
    Checked.new(summary: asked["summary"].to_s.strip, verify: asked["verify"].presence, steps: steps)
  end

  def self.order!(steps)
    positions = steps.map(&:position)
    steps.each do |step|
      unknown = step.depends_on - positions
      raise Refused, "Step #{step.position} depends on step #{unknown.first}, which the fix does not have." if unknown.any?
      raise Refused, "Step #{step.position} cannot depend on itself or a later step." if step.depends_on.any? { |position| position >= step.position }
    end
  end
  private_class_method :order!

  def self.propose!(finding, fix)
    checked = check!(finding.investigation.workspace, fix)
    transaction do
      plan = create!(finding: finding, summary: checked.summary, verify: checked.verify)
      checked.steps.each { |step| step.update!(plan: plan) }
      plan
    end
  end
end
