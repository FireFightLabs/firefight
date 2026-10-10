# A short plan Halon keeps in a chat for a request that takes more than one step, and updates as it goes. People see it as
# a checklist. Every change in it carries its undo before it runs, and a plan that changed something ends with a check
# that it worked. A plan can wait for a time a person approved, and then runs as them once a fresh reading says nothing
# moved in between.
class Chat::Plan < ApplicationRecord
  include Chat::SecretFree

  self.table_name = "chat_plans"

  # A plan with a time, waiting for a person to approve it.
  STATUS_PROPOSED = "proposed"
  # Approved, and waiting for its time.
  STATUS_SCHEDULED = "scheduled"
  STATUS_ACTIVE = "active"
  STATUS_COMPLETED = "completed"
  # A change failed, a check found the changes did not work, or a scheduled run found it should not start.
  STATUS_STOPPED = "stopped"
  STATUS_CANCELLED = "cancelled"
  STATUSES = [ STATUS_PROPOSED, STATUS_SCHEDULED, STATUS_ACTIVE, STATUS_COMPLETED, STATUS_STOPPED, STATUS_CANCELLED ].freeze
  # Still in play, which Halon is told about at the start of every turn.
  OPEN = [ STATUS_PROPOSED, STATUS_SCHEDULED, STATUS_ACTIVE, STATUS_STOPPED ].freeze
  NOT_STARTED = [ STATUS_PROPOSED, STATUS_SCHEDULED ].freeze
  ENDED = [ STATUS_COMPLETED, STATUS_STOPPED, STATUS_CANCELLED ].freeze
  # Over for good. A stopped plan can still be taken up again.
  FINISHED = [ STATUS_COMPLETED, STATUS_CANCELLED ].freeze

  # What a person may press on a plan, as its state offers it.
  ACTION_SCHEDULE = "schedule"
  ACTION_CANCEL = "cancel"
  ACTION_RETRY = "retry"
  ACTION_UNDO = "undo"
  ACTIONS = [ ACTION_SCHEDULE, ACTION_CANCEL, ACTION_RETRY, ACTION_UNDO ].freeze

  HEADINGS = {
    STATUS_PROPOSED => "Plan waiting for approval", STATUS_SCHEDULED => "Plan scheduled", STATUS_ACTIVE => "Plan in progress",
    STATUS_COMPLETED => "Plan done", STATUS_STOPPED => "Plan stopped", STATUS_CANCELLED => "Plan cancelled"
  }.freeze
  UNDO_HEADINGS = {
    STATUS_ACTIVE => "Undo in progress", STATUS_COMPLETED => "Plan undone", STATUS_STOPPED => "Undo stopped", STATUS_CANCELLED => "Undo cancelled"
  }.freeze

  MIN_STEPS = 2
  MAX_STEPS = 12
  GOAL_LIMIT = 300
  OUTCOME_LIMIT = 1_000
  LINKS_LIMIT = 10
  LATEST = 30.days

  # Raised when Halon's request cannot be carried out, with a reason it can act on.
  class Refused < StandardError; end

  belongs_to :chat
  belongs_to :workspace
  # Whoever the turn acted for when Halon made it.
  belongs_to :made_by, polymorphic: true, optional: true
  # The person who approved its time. A scheduled run acts as them.
  belongs_to :approved_by, class_name: "WorkspaceMembership", optional: true
  # An undo puts back what the plan it undoes changed.
  belongs_to :undoes, class_name: "Chat::Plan", optional: true
  has_one :undo_plan, class_name: "Chat::Plan", foreign_key: :undoes_id, inverse_of: :undoes, dependent: :nullify
  has_many :steps, -> { order(:position) }, class_name: "Chat::Plan::Step", foreign_key: :plan_id, inverse_of: :plan, dependent: :delete_all
  # Halon's reading of how things stand at its scheduled time, on a chat of its own.
  has_one :check, class_name: "Chat", as: :owner, dependent: :destroy

  validates :goal, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :state_change, inclusion: { in: Chat::CurrentState::CHANGES }, allow_nil: true

  scope :open, -> { where(status: OPEN) }

  def self.make!(chat:, made_by:, goal:, steps:, run_at: nil, time_zone: nil, undoes: nil)
    goal = goal.to_s.squish.truncate(GOAL_LIMIT)
    raise Refused, "A plan needs its goal, in the person's words." if goal.blank?

    checked = check_steps!(steps, scheduled: run_at.present?)
    check_time!(chat.workspace, run_at, time_zone) if run_at
    transaction do
      plan = create!(
        chat: chat, workspace: chat.workspace, made_by: made_by, goal: goal, undoes: undoes, run_at: run_at, time_zone: time_zone,
        status: run_at ? STATUS_PROPOSED : STATUS_ACTIVE, started_at: (Time.current unless run_at), moved_at: Time.current
      )
      checked.each { |step| step.update!(plan: plan) }
      plan
    end
  end

  # before is what a revision keeps, which counts towards the limit and the check that ends the plan.
  def self.check_steps!(steps, scheduled:, before: [])
    raise Refused, "A plan needs its steps as a list." unless steps.is_a?(Array) && steps.any?

    total = before.size + steps.size
    raise Refused, "A plan is for work of more than one step. Do a single step without one." if total < MIN_STEPS
    raise Refused, "A plan has at most #{MAX_STEPS} steps. Group the small ones." if total > MAX_STEPS

    checked = steps.each_with_index.map { |asked, index| Chat::Plan::Step.checked(asked, position: before.size + index + 1, scheduled: scheduled) }
    all = before + checked
    last_change = all.rindex(&:change?)
    if last_change && all.drop(last_change + 1).none?(&:check?)
      raise Refused, "A plan that changes something ends with a check step after its last change, reading health, error rate and " \
                     "latency against normal."
    end
    checked
  end

  # Ends a sentence a model wrote, which may or may not have its stop.
  def self.sentence(text)
    said = text.to_s.strip
    said.match?(/[.!?]\z/) ? said : "#{said}."
  end

  def self.check_time!(workspace, run_at, time_zone)
    raise Refused, "That time has passed. Pick one after now." unless run_at > Time.current
    raise Refused, "A plan is scheduled at most #{LATEST.in_days.to_i} days ahead." if run_at > LATEST.from_now

    window = Workspace::FreezeWindows.covering(workspace, run_at)
    raise Refused, "#{Workspace::FreezeWindows.sentence(window, time_zone)} Offer the person a time after it." if window
  end
  private_class_method :check_time!

  def proposed? = status == STATUS_PROPOSED
  def scheduled? = status == STATUS_SCHEDULED
  def active? = status == STATUS_ACTIVE
  def stopped? = status == STATUS_STOPPED
  def completed? = status == STATUS_COMPLETED
  def undo? = undoes_id.present?

  def conversation = chat.owner

  # The tools a scheduled run may call without asking, since the person approved the plan naming each. Approval rules
  # still hold every one of them.
  def approved_tools = scheduled_run? ? steps.select(&:change?).filter_map(&:tool) : []

  def scheduled_run? = run_at.present? && approved_by_id.present?

  # Replaces the steps that have not started, keeping those that have, in their order.
  def revise!(asked)
    raise Refused, "#{goal_named} is scheduled. Cancel it with cancel_plan and propose it again." if scheduled?
    raise Refused, "#{goal_named} has ended. Make a new plan." if FINISHED.include?(status)

    with_lock do
      kept = steps.reject(&:not_started?)
      checked = self.class.check_steps!(asked, scheduled: run_at.present?, before: kept)
      steps.where(status: Chat::Plan::Step::STATUS_NOT_STARTED).delete_all
      # Two passes, since a position is unique within a plan.
      kept.each_with_index { |step, index| step.update_columns(position: -(index + 1)) }
      kept.each_with_index { |step, index| step.update_columns(position: index + 1) }
      checked.each { |step| step.update!(plan: self) }
      touch_moved!
    end
    steps.reset
    self
  end

  # read_since says whether Halon read anything through a connection since a time, which a check needs after a change.
  def move_step!(position, status:, note: nil, links: [], verdict: nil, undo: nil, read_since: ->(_time) { true })
    step = steps.find_by(position: position.to_i)
    raise Refused, "#{goal_named} has no step #{position}." unless step

    blocked = step_blocked_reason
    raise Refused, blocked if blocked

    step.undo = undo.to_s.strip if undo.present?
    blocked = step.move_blocked_reason(status, verdict: verdict)
    raise Refused, blocked if blocked
    if read_needed?(step, status, verdict) && (changed_at = last_change_at) && !read_since.call(changed_at)
      raise Refused, "Read how it stands since the last change ended, with resource_status and run_key_query against normal, before you mark the check done."
    end

    with_lock do
      step.assign_attributes(
        status: status, note: note.to_s.strip.truncate(Chat::Plan::Step::NOTE_LIMIT).presence || step.note,
        links: clean_links(links, Chat::Plan::Step::LINKS_LIMIT).presence || step.links,
        verdict: (verdict.presence if step.check?), started_at: step.started_at || Time.current,
        finished_at: (Time.current if Chat::Plan::Step::ENDED.include?(status))
      )
      raise Refused, "Step #{position} #{step.errors.full_messages.to_sentence.downcase}." unless step.save

      resume! if stopped? && status == Chat::Plan::Step::STATUS_RUNNING
      stop!(stopped_for(step)) if stopping?(step)
      touch_moved!
    end
    step
  end

  # Ends it once the last step ended, with what came of it and what to do next.
  def finish!(outcome:, next_step:, links: [])
    blocked = finish_blocked_reason(next_step)
    raise Refused, blocked if blocked

    moved = self.class.where(id: id, status: STATUS_ACTIVE).update_all(
      status: STATUS_COMPLETED, finished_at: Time.current, moved_at: Time.current, updated_at: Time.current,
      outcome: outcome.to_s.strip.truncate(OUTCOME_LIMIT).presence, next_step: next_step.to_s.strip.truncate(OUTCOME_LIMIT),
      links: clean_links(links, LINKS_LIMIT)
    )
    reload
    raise Refused, "#{goal_named} is no longer going." unless moved == 1

    self
  end

  def finish_blocked_reason(next_step)
    return "#{goal_named} is #{status_words}, so it cannot be finished." unless active?

    left = steps.reject(&:ended?)
    return "#{'Step'.pluralize(left.size)} #{left.map(&:position).to_sentence} #{left.one? ? 'has' : 'have'} not ended. Mark each done, failed or skipped first." if left.any?

    last_change = steps.select { |step| step.change? && step.done? }.max_by(&:position)
    if last_change && steps.none? { |step| step.check? && step.done? && step.position > last_change.position }
      return "Step #{last_change.position} changed something, so check it worked before you finish: a check step after it, done with what you read."
    end
    return "Say the most useful next step for the person, as next_step." if next_step.to_s.strip.blank?

    nil
  end

  # Ends it from anywhere it is still in play. False when it had already ended.
  def cancel!(reason: nil)
    moved = self.class.where(id: id, status: OPEN).update_all(
      status: STATUS_CANCELLED, stop_reason: reason, finished_at: Time.current, moved_at: Time.current, updated_at: Time.current
    )
    reload
    moved == 1
  end

  # Claims the approval for one person. False when someone got there first.
  def approve!(by:)
    moved = self.class.where(id: id, status: STATUS_PROPOSED).update_all(
      status: STATUS_SCHEDULED, approved_by_id: by.id, approved_at: Time.current, moved_at: Time.current, updated_at: Time.current
    )
    reload
    moved == 1
  end

  # Claims the scheduled run, so two workers never start it twice.
  def claim_run!(now = Time.current)
    moved = self.class.where(id: id, status: STATUS_SCHEDULED).where(run_at: ..now)
                      .update_all(status: STATUS_ACTIVE, started_at: now, moved_at: now, updated_at: now)
    reload
    moved == 1
  end

  # From going, or from waiting for its time when the run found it should not start.
  def stop!(reason)
    moved = self.class.where(id: id, status: [ STATUS_ACTIVE, STATUS_SCHEDULED ])
                      .update_all(status: STATUS_STOPPED, stop_reason: reason, moved_at: Time.current, updated_at: Time.current)
    reload
    moved == 1
  end

  # Back to going after it stopped, from Retry or from Halon starting a step again.
  def resume!
    moved = self.class.where(id: id, status: STATUS_STOPPED).update_all(status: STATUS_ACTIVE, stop_reason: nil, moved_at: Time.current, updated_at: Time.current)
    reload
    moved == 1
  end

  # Claims the undo for one person, so two clicks make one.
  def claim_undo!
    self.class.where(id: id, undo_requested_at: nil).update_all(undo_requested_at: Time.current, updated_at: Time.current) == 1
  end

  def checked!(report)
    update!(state_now: report.state, state_change: report.change, state_checked_at: report.checked_at)
  end

  # Whoever a dashboard chat belongs to may approve, cancel, retry or undo its plans, and so may anyone in the channel for
  # a chat in one. A plan in another agent's chat has nobody to press anything.
  def may_act?(member)
    owner = conversation
    return false unless member.is_a?(WorkspaceMembership) && member.workspace_id == workspace_id && owner.is_a?(Conversation)

    owner.personal? ? owner.started_by == member : owner.kind == Conversation::KIND_CHANNEL
  end

  def only_who_may = "Only #{conversation.try(:started_by).try(:display_name) || 'whoever this chat belongs to'} can do that."

  def approve_blocked_reason(member)
    return "This plan is not waiting to be scheduled." unless proposed?
    return "Its time has passed. Ask Halon for a new one." unless run_at&.future?
    return only_who_may unless may_act?(member)

    window = Workspace::FreezeWindows.covering(workspace, run_at)
    return Workspace::FreezeWindows.sentence(window, time_zone) if window

    Investigation.unavailable_reason(workspace)
  end

  def cancel_blocked_reason(member)
    return "Only a plan that has not started can be cancelled here. Ask Halon to stop one that is going." unless NOT_STARTED.include?(status)
    return only_who_may unless may_act?(member)

    nil
  end

  def retry_blocked_reason(member)
    return "Only a plan that stopped can be tried again." unless stopped?
    return only_who_may unless may_act?(member)

    Investigation.unavailable_reason(workspace)
  end

  def undo_blocked_reason(member)
    return "This is already the undo of a plan." if undo?
    return "Undo is offered once the plan has stopped or finished." unless ENDED.include?(status)
    return "Nothing in this plan changed anything, so there is nothing to undo." unless steps.any? { |step| step.change? && step.done? }
    undone = Chat::Mitigation.undone_steps(self)
    if steps.none? { |step| step.change? && step.done? && undone.exclude?(step.id) }
      return "Firefight already put back every change in this plan when its time ran out, so there is nothing left to undo."
    end
    return "Its undo is already under way." if undo_requested_at || undo_plan
    return only_who_may unless may_act?(member)

    Investigation.unavailable_reason(workspace)
  end

  # What its state offers, whoever looks. Each still has its own blocked reason for the person pressing it.
  def offers
    case status
    when STATUS_PROPOSED then [ ACTION_SCHEDULE, ACTION_CANCEL ]
    when STATUS_SCHEDULED then [ ACTION_CANCEL ]
    when STATUS_STOPPED then undo_requested_at ? [] : [ ACTION_RETRY, (ACTION_UNDO if undoable?) ].compact
    when STATUS_COMPLETED, STATUS_CANCELLED then undoable? ? [ ACTION_UNDO ] : []
    else []
    end
  end

  def blocked_reason(action, member)
    case action
    when ACTION_SCHEDULE then approve_blocked_reason(member)
    when ACTION_CANCEL then cancel_blocked_reason(member)
    when ACTION_RETRY then retry_blocked_reason(member)
    else undo_blocked_reason(member)
    end
  end

  def undoable? = !undo? && undo_requested_at.nil? && steps.any? { |step| step.change? && step.done? }

  def heading = (undo? && UNDO_HEADINGS[status]) || HEADINGS.fetch(status)

  # The line under the heading, saying when it runs or how far it got.
  def progress_words
    return "Runs #{run_at_words}#{", approved by #{approved_by.display_name}" if approved_by}." if NOT_STARTED.include?(status)

    "#{done_count} of #{steps.size} steps done."
  end

  # The undo, from the undo each change was written with before it ran, newest first, then a check that it is back.
  # A change Firefight already undid when its time ran out (Chat::Mitigation) is left out, so it is put back once.
  def undo_steps
    undone = Chat::Mitigation.undone_steps(self)
    changed = steps.select { |step| step.change? && step.done? && undone.exclude?(step.id) }.sort_by(&:position).reverse
    rows = changed.map do |step|
      { "kind" => Chat::Plan::Step::KIND_CHANGE, "description" => "Put back step #{step.position}: #{step.undo}", "place" => step.place,
        "undo" => "Do step #{step.position} again: #{step.description}" }
    end
    places = changed.filter_map(&:place).uniq
    rows << { "kind" => Chat::Plan::Step::KIND_CHECK, "place" => places.to_sentence.presence,
              "description" => "Check it is back to how it was before: health, error rate and latency against normal" }
  end

  # Done, failed with why and not started, the way a partial failure is reported.
  def standing
    done = steps.select(&:done?).map(&:position)
    left = steps.select(&:not_started?).map(&:position)
    [
      ("Done: #{'step'.pluralize(done.size)} #{done.to_sentence}." if done.any?),
      *steps.select(&:failed?).map { |step| "Failed: step #{step.position}.#{" #{self.class.sentence(step.note)}" if step.note.present?}" },
      ("Not started: #{'step'.pluralize(left.size)} #{left.to_sentence}." if left.any?)
    ].compact.join(" ")
  end

  def done_count = steps.count(&:done?)

  def status_words = status.tr("_", " ")

  def goal_named = "The plan to #{goal.sub(/\A[A-Z](?=[a-z])/, &:downcase)}".delete_suffix(".")

  # When it runs, in its own time zone, such as Saturday 11 October at 06:00 CEST.
  def run_at_words = run_at&.in_time_zone(time_zone.presence || "UTC")&.strftime("%A %-d %B at %H:%M %Z")

  def text = [ goal, outcome, next_step ].compact.join(" ")

  private

  def step_blocked_reason
    return "#{goal_named} runs #{run_at_words}, and nothing in it starts before then." if NOT_STARTED.include?(status)
    return "#{goal_named} is #{status_words}. Make a new plan for more work." if FINISHED.include?(status)

    nil
  end

  # A check saying it could not tell needs no reading, since it says none could be made.
  def read_needed?(step, status, verdict)
    step.check? && status == Chat::Plan::Step::STATUS_DONE && verdict.to_s != Chat::Plan::Step::VERDICT_UNKNOWN
  end

  def last_change_at = steps.select { |step| step.change? && step.done? }.filter_map(&:finished_at).max

  def stopping?(step)
    (step.change? && step.failed?) || (step.check? && step.done? && step.verdict == Chat::Plan::Step::VERDICT_NOT_HELD)
  end

  def stopped_for(step)
    said = (" #{self.class.sentence(step.note)}" if step.note.present?)
    return "Step #{step.position} failed.#{said}" if step.failed?

    "The check found the changes did not work.#{said}"
  end

  def touch_moved! = update_columns(moved_at: Time.current, updated_at: Time.current)

  def clean_links(links, limit)
    Array(links).map { |link| link.to_s.strip }.select { |link| link.match?(%r{\Ahttps?://\S+\z}) }.uniq.first(limit)
  end
end
