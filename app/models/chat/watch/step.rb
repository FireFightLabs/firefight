# One thing a watch follows, read through one capability as the person who asked: a run in a resource's history (a CI
# run, a build, a deploy), or a reading such as a resource's status that says when it is done or failed. Each milestone
# is claimed by one guarded update, so it is reported once.
class Chat::Watch::Step < ApplicationRecord
  STATUS_WAITING = "waiting"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  # It could not be read any more, such as a permission taken away, so the watch no longer follows it.
  STATUS_UNFOLLOWABLE = "unfollowable"
  STATUSES = [ STATUS_WAITING, STATUS_RUNNING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE ].freeze
  OVER = [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE ].freeze
  # Running this much longer than usual is worth saying, once.
  SLOW_AFTER = 1.5
  SLOW_AT_LEAST = 2.minutes
  # A run that started this long before the watch is still the one asked about, since a person asks after starting it.
  STARTED_BEFORE_WATCH = 10.minutes
  STATE_LIMIT = 1_000
  # A step that reads one of Halon's read tools by name, rather than a capability.
  READ_TOOL = "read_tool"
  # A run that has not shown up in its history this long after it could have is handed back to Halon to find another
  # way to follow it, rather than waited on in silence for the whole limit.
  HAND_BACK_AFTER = 3.minutes

  # How a job or step inside what it follows stands, in the words its progress is said in.
  PART_WAITING = "waiting"
  PART_RUNNING = "running"
  PART_PASSED = "passed"
  PART_FAILED = "failed"
  # Starting and passing are said as progress. A failed job inside a run is said on its own with why, and one a reading
  # shows is said with the progress, since nothing else says it.
  PART_SAID = [ PART_RUNNING, PART_PASSED ].freeze
  READING_SAID = [ PART_RUNNING, PART_PASSED, PART_FAILED ].freeze

  belongs_to :watch, class_name: "Chat::Watch", inverse_of: :steps
  belongs_to :integration_environment, optional: true

  validates :status, inclusion: { in: STATUSES }

  # A read a watch can make, by its key or the name Halon calls it. Nil for one that writes or that nothing knows.
  def self.read_key(name)
    spec = Integrations::Capabilities::SPECS.values.find { |each| each.tool_name == name.to_s || each.key == name.to_s }
    spec.key if spec && !spec.writes
  end

  # Whether a step given to start_watch, with string keys, lacks what counts as its end. A run in a resource's history
  # ends on its own, anything else needs done_when, failed_when or a goal. Checked when a runbook saves and when a watch starts.
  def self.undecided?(step)
    keys = Chat::Watch::SPEC_KEYS
    return false if step["tool"].blank? && read_key(step[keys[:capability]]) == Integrations::Capabilities::HISTORY

    step.values_at(keys[:done_when], keys[:failed_when], keys[:goal]).all?(&:blank?)
  end

  def history? = capability == Integrations::Capabilities::HISTORY

  def read_tool? = capability == READ_TOOL

  def spec = Integrations::Capabilities.spec(capability)

  def over? = OVER.include?(status)

  def running? = status == STATUS_RUNNING

  # The run this step follows among those a history read found: the one it already follows, the one the person named,
  # or the first of its name that started around or after the watch began.
  def run_among(runs)
    return runs.find { |run| run.id.to_s == followed_run_id } if followed_run_id.present?
    return runs.find { |run| run.named?(run_ref) } if run_ref.present?

    since = watch.created_at - STARTED_BEFORE_WATCH
    runs.select { |run| run.called?(run_name) && run.started_at && run.started_at >= since && !finished_before_watch?(run) }
        .min_by(&:started_at)
  end

  # Whether it ran this long past its usual time and has not said so yet.
  def slow?(now = Time.current)
    return false unless running? && started_at && usual_seconds.to_i.positive? && slow_told_at.nil?

    elapsed = now - started_at
    elapsed > usual_seconds * SLOW_AFTER && elapsed > usual_seconds + SLOW_AT_LEAST
  end

  # The run or reading was seen going. True once, for whoever saw it first.
  def started!(run_id:, at:, url: nil)
    claim(started_told_at: nil) { { status: STATUS_RUNNING, followed_run_id: run_id, started_at: at || Time.current, run_url: url, started_told_at: Time.current } }
  end

  # The run or reading is over. True once, for whoever saw it first.
  def finished!(status, reason: nil, at: nil, run_id: nil, url: nil, started: nil)
    claim(finished_told_at: nil) do
      { status: status, reason: reason&.truncate(STATE_LIMIT), finished_at: at || Time.current, finished_told_at: Time.current,
        followed_run_id: run_id || followed_run_id, run_url: url || run_url, started_at: started_at || started || at }
    end
  end

  def slow_told! = claim(slow_told_at: nil) { { slow_told_at: Time.current } }

  # A job or step inside the run failed while the run went on. True once, for whoever saw it first.
  def part_failed!(name) = claim(failed_part_told_at: nil) { { failed_part: name.to_s.truncate(200), failed_part_told_at: Time.current } }

  # No run showed up, so Halon is asked to find another way to follow it. True once.
  def handed_back! = claim(handed_back_at: nil) { { handed_back_at: Time.current } }

  # Waiting on a run that has not shown up since it could have: since the watch began, or since the step before it ended.
  def overdue?(now = Time.current)
    return false unless history? && status == STATUS_WAITING && handed_back_at.nil?

    earlier = watch.steps.select { |step| step.position < position }
    return false unless earlier.all?(&:over?)

    since = [ watch.created_at, *earlier.filter_map(&:finished_at) ].max
    now - since >= HAND_BACK_AFTER
  end

  def unfollowable!(reason) = finished!(STATUS_UNFOLLOWABLE, reason: reason)

  # Each job or step whose state moved since it was last said, as "tag passed" or "build running", kept so each is said
  # once. parts are [name, state] pairs in their order. Only the check holding the watch writes this.
  def progress!(parts, said: PART_SAID)
    moved = parts.reject { |name, state| parts_told[name] == state || (state == PART_RUNNING && parts_told[name] == PART_PASSED) }
    return [] if moved.empty?

    update_columns(parts_told: parts_told.merge(moved.to_h), updated_at: Time.current)
    moved.select { |_name, state| said.include?(state) }.map { |name, state| "#{name} #{state}" }
  end

  # The jobs or steps that passed so far, in the order they were said.
  def parts_passed = parts_told.select { |_name, state| state == PART_PASSED }.keys

  # What a read showed last, kept so a check that sees nothing new asks no model.
  def seen!(digest:, state:)
    update_columns(last_digest: digest, last_state: state.to_s.truncate(STATE_LIMIT), updated_at: Time.current)
  end

  def seconds_taken
    return unless started_at && finished_at

    (finished_at - started_at).round
  end

  private

  def finished_before_watch?(run) = run.finished? && run.finished_at && run.finished_at < watch.created_at

  def claim(unset)
    moved = self.class.where(id: id, **unset).update_all(**yield, updated_at: Time.current)
    reload
    moved == 1
  end
end
