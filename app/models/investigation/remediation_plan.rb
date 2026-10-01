# How to fix what a run found, written by the agent when it names a cause: ordered steps, how to tell it worked, and who
# applied it. Every finding with a cause has one, whether or not anything can apply it, since a fix nobody can run is
# still steps for a person. Applying it is a person's decision, never part of writing it, and its steps then run as that
# person (approved_by), through their own permissions.
class Investigation::RemediationPlan < ApplicationRecord
  self.table_name = "investigation_remediation_plans"

  STATUS_PROPOSED = "proposed".freeze
  STATUS_APPLYING = "applying".freeze
  STATUS_APPLIED = "applied".freeze
  STATUS_PARTLY_APPLIED = "partly_applied".freeze
  STATUSES = [ STATUS_PROPOSED, STATUS_APPLYING, STATUS_APPLIED, STATUS_PARTLY_APPLIED ].freeze
  # Where a person applied it, which the ledger names as the source of each step.
  APPLIED_FROM = AbilityGateway::HUMAN_SOURCES

  # Raised when a proposal cannot be recorded, with a reason the agent can act on.
  class Refused < StandardError; end

  # A proposal checked against what the workspace can run, and not saved yet.
  Checked = Data.define(:summary, :verify, :steps)

  belongs_to :finding, class_name: "Investigation::Finding"
  belongs_to :approved_by, class_name: "WorkspaceMembership", optional: true
  has_many :steps, -> { order(:position) }, class_name: "Investigation::RemediationStep", foreign_key: :plan_id, inverse_of: :plan,
                                             dependent: :destroy

  scope :in_workspace, ->(workspace) { joins(finding: :investigation).where(investigations: { workspace_id: workspace.id }) }

  validates :summary, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :applied_from, inclusion: { in: APPLIED_FROM }, allow_nil: true

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

  # Whether anything in it runs through a connection. A fix that is all steps for people is never applied, only marked
  # done step by step.
  def appliable? = steps.any?(&:action?)

  def applying? = status == STATUS_APPLYING

  # Why this fix cannot be applied now, or nil. Without a person, only what holds for everyone, which the run page shows.
  # With one, also whether they may run every tool it needs, so nothing starts that would stop partway for want of access.
  def apply_blocked_reason(membership = nil)
    return "Nothing in this fix runs through a connection, so each step is marked done by hand." unless appliable?
    return "#{approved_by&.display_name || 'Someone'} already applied this fix." unless status == STATUS_PROPOSED

    workspace = finding.investigation.workspace
    resolved = membership && Ability::Resolver.resolve(membership, workspace)
    steps.select(&:action?).each do |step|
      tool = step.tool_to_run(workspace)
      return "Step #{step.position} runs #{step.tool_name}, which is no longer switched on." unless tool
      if membership && !tool.callable_by?(membership, resolved)
        return "Step #{step.position} runs #{step.tool_name}, which you have no access to. An admin can grant it under Permissions."
      end
    end
    nil
  end

  # Claims the fix for one person, so two clicks never apply it twice. False when someone else got there first.
  def apply!(by:, from:)
    won = self.class.where(id: id, status: STATUS_PROPOSED)
                    .update_all(status: STATUS_APPLYING, approved_by_id: by.id, approved_at: Time.current, applied_from: from, updated_at: Time.current)
    reload
    won == 1
  end

  # Once every step has ended, applied when each one was done, partly applied otherwise.
  def settle!
    current = steps.reload
    return unless current.all?(&:ended?)

    ended = current.all?(&:done?) ? STATUS_APPLIED : STATUS_PARTLY_APPLIED
    self.class.where(id: id, status: [ STATUS_PROPOSED, STATUS_APPLYING ]).update_all(status: ended, updated_at: Time.current)
    reload
  end

  # Whether anything is moving on its own now, which is when the run page keeps itself current. A step held for approval
  # or waiting on a person is not, so the page does not poll for hours.
  def moving?
    applying? && steps.any? { |step| step.status == Investigation::RemediationStep::STATUS_RUNNING || (step.action? && step.proposed? && step.ready?(steps)) }
  end

  # Claims the one progress message, so two workers never post two. False when one is already there.
  def claim_progress_message!(channel_id:, message_id:)
    won = self.class.where(id: id, progress_message_id: nil).update_all(progress_channel_id: channel_id, progress_message_id: message_id, updated_at: Time.current)
    reload
    won == 1
  end

  def self.propose!(finding, fix)
    checked = check!(finding.investigation.workspace, fix)
    transaction do
      plan = create!(finding: finding, summary: checked.summary, verify: checked.verify)
      checked.steps.each { |step| step.update!(plan: plan) }
      plan
    end
  end
end
