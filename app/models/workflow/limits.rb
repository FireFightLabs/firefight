# What keeps a workflow from running away: how many runs it starts an hour, one live run per subject when it names one
# (such as one per service), and, for runs an event starts, a ceiling the whole workspace shares each hour so a storm of
# events never starts a hundred runs. A run's AI ceiling is cost_cap_cents, which has no default.
module Workflow::Limits
  extend ActiveSupport::Concern

  RUNS_PER_HOUR = (1..1_000)
  EVENT_RUNS_PER_HOUR = (1..10_000)
  SUBJECT_KEY_LIMIT = 200
  # Runs that start by hand, on a schedule, once at a time or from another workflow. Anything else is an event.
  NOT_EVENTS = [ Workflow::Trigger::KIND_MANUAL, Workflow::Trigger::KIND_SCHEDULE, Workflow::Trigger::KIND_ONCE_AT, Workflow::Trigger::KIND_CALLED ].freeze

  included do
    validates :runs_per_hour, numericality: { only_integer: true, in: RUNS_PER_HOUR }
    validates :subject_key, length: { maximum: SUBJECT_KEY_LIMIT }, allow_nil: true
    validate :subject_key_reads_the_run
  end

  class_methods do
    # Why an event cannot start another run this hour, or nil.
    def event_blocked_reason(workspace, now: Time.current)
      started = Workflow::Run.where(workspace: workspace, test: false, created_at: (now - 1.hour)..).where.not(trigger_kind: NOT_EVENTS).count
      return if started < workspace.workflow_event_runs_per_hour

      "Events already started #{started} workflow runs in this workspace in the last hour, which is as many as it allows, so this one did not start."
    end
  end

  # Why it cannot start another run this hour, or nil. Test runs do not count.
  def rate_blocked_reason(now: Time.current)
    started = runs.where(test: false, created_at: (now - 1.hour)..).count
    return if started < runs_per_hour

    "#{name} already started #{started} #{'run'.pluralize(started)} in the last hour, which is as many as it allows, so this one did not start."
  end

  # The subject a run is about, filled from what started it, so one live run per subject is kept. nil without one.
  def subject_for(inputs:, trigger_payload:)
    return if subject_key.blank?

    filled = Workflow::Version.filled(subject_key, Workflow::Version::ROOT_INPUTS => inputs.to_h, Workflow::Version::ROOT_TRIGGER => trigger_payload.to_h)
    filled.to_s.strip.presence
  end

  private

  def subject_key_reads_the_run
    return if subject_key.blank?

    roots = Workflow::Version.references_in(subject_key).map { |path| path.split(".").first }
    return errors.add(:subject_key, "names what a run is about with a reference such as {{inputs.service}}") if roots.empty?

    allowed = [ Workflow::Version::ROOT_INPUTS, Workflow::Version::ROOT_TRIGGER ]
    errors.add(:subject_key, "reads only the inputs or the trigger, which a run knows when it starts") unless roots.all? { |root| allowed.include?(root) }
  end
end
