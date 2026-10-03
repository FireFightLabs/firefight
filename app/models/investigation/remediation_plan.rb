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
  # Stopped by a person while it was being applied. What went through stays, and can be undone.
  STATUS_CANCELLED = "cancelled".freeze
  STATUSES = [ STATUS_PROPOSED, STATUS_APPLYING, STATUS_APPLIED, STATUS_PARTLY_APPLIED, STATUS_CANCELLED ].freeze
  ENDED_WITH_CHANGES = [ STATUS_APPLIED, STATUS_PARTLY_APPLIED, STATUS_CANCELLED ].freeze
  # Where a person applied it, which the ledger names as the source of each step.
  APPLIED_FROM = AbilityGateway::HUMAN_SOURCES

  # Raised when a proposal cannot be recorded, with a reason the agent can act on.
  class Refused < StandardError; end

  # A proposal checked against what the workspace can run, and not saved yet.
  Checked = Data.define(:summary, :verify, :steps)

  belongs_to :finding, class_name: "Investigation::Finding"
  belongs_to :approved_by, class_name: "WorkspaceMembership", optional: true
  # An undo reverses the fix it undoes, and is applied the same way.
  belongs_to :undoes, class_name: "Investigation::RemediationPlan", optional: true
  has_one :undo_plan, class_name: "Investigation::RemediationPlan", foreign_key: :undoes_id, inverse_of: :undoes, dependent: :destroy
  belongs_to :undo_requested_by, class_name: "WorkspaceMembership", optional: true
  belongs_to :cancelled_by, class_name: "WorkspaceMembership", optional: true
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
  def appliable? = steps.any?(&:runs_itself?)

  def applying? = status == STATUS_APPLYING

  # Why this fix cannot be applied now, or nil. Without a person, only what holds for everyone, which the run page shows.
  # With one, also whether they may run every tool it needs, so nothing starts that would stop partway for want of access.
  def apply_blocked_reason(membership = nil)
    return "Nothing in this fix runs through a connection, so each step is marked done by hand." unless appliable?
    return "#{approved_by&.display_name || 'Someone'} already applied this fix." unless status == STATUS_PROPOSED

    workspace = finding.investigation.workspace
    resolved = membership && Ability::Resolver.resolve(membership, workspace)
    steps.select { |step| step.runs_itself?(workspace) }.each do |step|
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
    return true if writing_undo?
    # A step still running after the fix was cancelled is still worth watching finish.
    return true if steps.any? { |step| step.status == Investigation::RemediationStep::STATUS_RUNNING }

    applying? && steps.any? { |step| step.status == Investigation::RemediationStep::STATUS_RUNNING || (step.runs_itself? && step.proposed? && step.ready?(steps)) }
  end

  def undo? = undoes_id.present?

  # Writing an undo is one model call, so one asked for longer ago than this lost its worker and can be asked again.
  UNDO_WRITING_STALE_AFTER = 10.minutes

  def writing_undo? = undo_requested_at.present? && undo_requested_at > UNDO_WRITING_STALE_AFTER.ago && undo_plan.nil? && undo_error.nil?

  # Why this fix cannot be undone now, or nil. Only what went through changed anything to put back.
  def undo_blocked_reason
    return "This is already the undo of a fix." if undo?
    return "Only a fix that was applied can be undone." unless ENDED_WITH_CHANGES.include?(status)
    return "Nothing in this fix went through, so there is nothing to undo." if steps.none?(&:done?)
    return "A step is still running or waiting for approval. Undo once it has ended." if steps.any? { |step| [ Investigation::RemediationStep::STATUS_RUNNING, Investigation::RemediationStep::STATUS_WAITING_APPROVAL ].include?(step.status) }
    return "Halon is writing the undo." if writing_undo?
    return "Its undo is already written, to apply like the fix." if undo_plan

    Investigation.unavailable_reason(finding.investigation.workspace)
  end

  def cancel_blocked_reason
    return "Only a fix being applied can be cancelled." unless applying?

    nil
  end

  # Stops the fix for one person, so a step that has not started never will. A step already running finishes, since a
  # call cannot be taken back halfway. False when it was no longer being applied.
  def cancel!(by:)
    won = transaction do
      self.class.where(id: id, status: STATUS_APPLYING)
                .update_all(status: STATUS_CANCELLED, cancelled_by_id: by.id, cancelled_at: Time.current, updated_at: Time.current)
    end
    reload
    won == 1
  end

  def cancelled? = status == STATUS_CANCELLED

  # Whoever the fix's latest word belongs to, the person who cancelled it or the one who applied it.
  def last_moved_by = cancelled? ? cancelled_by : approved_by

  # Claims writing the undo for one person, so two clicks write it once. A failed or lost writing can be asked again.
  def request_undo!(by:)
    stale = UNDO_WRITING_STALE_AFTER.ago
    won = self.class.where(id: id).where("undo_requested_at IS NULL OR undo_error IS NOT NULL OR undo_requested_at < ?", stale)
                    .update_all(undo_requested_at: Time.current, undo_requested_by_id: by.id, undo_error: nil, updated_at: Time.current)
    reload
    won == 1
  end

  def undo_failed!(reason)
    update!(undo_error: reason)
  end

  # The undo, checked like any fix, on the same finding.
  def propose_undo!(fix)
    checked = self.class.check!(finding.investigation.workspace, fix)
    transaction do
      plan = self.class.create!(finding: finding, undoes: self, summary: checked.summary, verify: checked.verify)
      checked.steps.each { |step| step.update!(plan: plan) }
      plan
    end
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
