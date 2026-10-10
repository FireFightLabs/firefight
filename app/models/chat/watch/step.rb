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
  # Its read found nothing to follow, so Halon is picking a better one for it with repair_watch. It is not read meanwhile.
  STATUS_REPAIRING = "repairing"
  STATUSES = [ STATUS_WAITING, STATUS_RUNNING, STATUS_REPAIRING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE ].freeze
  OVER = [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE ].freeze
  # A step Halon may still change the read of.
  OPEN = [ STATUS_WAITING, STATUS_RUNNING, STATUS_REPAIRING ].freeze
  # Halon picks a better read this many times for one step. Past that the step is no longer followed, rather than
  # reading one wrong thing after another.
  MAX_REPAIRS = 2
  # A repair Halon has not made in this long, such as when the chat waits on the person, leaves the step unfollowed.
  REPAIR_WITHIN = 15.minutes
  # A reading that stays the same is judged again this often, so a condition that names a time, such as healthy for
  # ten minutes, is decided without a model call every minute.
  JUDGE_STEADY_EVERY = 5.minutes
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

  # What a read is called where a person picks it, such as Run history.
  def self.read_label(spec) = spec.what.upcase_first

  # What a step given to start_watch, with string keys, is called when it names nothing. That is the read tool it names,
  # as tool_title calls it, or what it reads. Nil when it names neither.
  def self.default_label(step, &tool_title)
    tool = step[Chat::Watch::SPEC_KEYS[:tool]]
    return (tool_title ? tool_title.call(tool.to_s) : tool.to_s) if tool.present?

    key = read_key(step[Chat::Watch::SPEC_KEYS[:capability]])
    key && read_label(Integrations::Capabilities.spec(key))
  end

  # Whether a step given to start_watch, with string keys, lacks what counts as its end. A run in a resource's history
  # ends on its own, anything else needs done_when, failed_when or a goal. Checked when a runbook saves and when a watch starts.
  def self.undecided?(step)
    keys = Chat::Watch::SPEC_KEYS
    return false if step[keys[:tool]].blank? && read_key(step[keys[:capability]]) == Integrations::Capabilities::HISTORY

    step.values_at(keys[:done_when], keys[:failed_when], keys[:goal]).all?(&:blank?)
  end

  def history? = capability == Integrations::Capabilities::HISTORY

  def read_tool? = capability == READ_TOOL

  def spec = Integrations::Capabilities.spec(capability)

  def over? = OVER.include?(status)

  def running? = status == STATUS_RUNNING

  def repairing? = status == STATUS_REPAIRING

  # Whether Halon may give it a better read once more.
  def repairable? = repairs < MAX_REPAIRS

  # Waiting on a repair longer than Halon has to make one.
  def repair_overdue?(now = Time.current) = repairing? && handed_back_at.present? && now - handed_back_at >= REPAIR_WITHIN

  # Its reading has not changed, and was not judged within JUDGE_STEADY_EVERY, so it is judged again.
  def judge_again?(now = Time.current) = judged_at.nil? || now - judged_at >= JUDGE_STEADY_EVERY

  # The read it makes, as a person reads it, such as "Run history of firefight" or "northflank_api_request GET
  # workflows/release/runs/46".
  def read_words
    if read_tool?
      # By name, since a stored read keeps no order of its own.
      given = arguments.sort.map(&:last).select { |value| value.is_a?(String) || value.is_a?(Numeric) }
      return [ tool_name, *given ].join(" ").truncate(160)
    end

    resource = arguments[Integrations::Capabilities::RESOURCE_ARG].presence
    [ Chat::Watch::Step.read_label(spec), (" of #{resource}" if resource) ].join
  end

  # Its read found nothing to follow, so Halon is asked for a better one. True once, for whoever saw it first, and only
  # from a status it may leave.
  def repair_asked!(reason, now = Time.current)
    moved = self.class.where(id: id, status: [ STATUS_WAITING, STATUS_RUNNING ], handed_back_at: nil)
                      .update_all(status: STATUS_REPAIRING, repair_reason: reason.to_s.truncate(STATE_LIMIT), handed_back_at: now, hand_back_noted_at: nil, updated_at: now)
    reload
    moved == 1
  end

  # Follows it with another read from here on, starting over as if the watch began now. Only while it is still open,
  # so a step that ended meanwhile keeps its end. False when it had ended.
  def repaired!(read)
    moved = self.class.where(id: id, status: OPEN).update_all(
      **read, status: STATUS_WAITING, repairs: Arel.sql("repairs + 1"), repaired_at: Time.current, repair_reason: nil, handed_back_at: nil, hand_back_noted_at: nil,
              followed_run_id: nil, run_url: nil, started_at: nil, started_told_at: nil, slow_told_at: nil, failed_part: nil,
              failed_part_told_at: nil, parts_told: {}, last_digest: nil, last_state: nil, judged_at: nil, steady_since: nil, read_at: nil,
              updated_at: Time.current
    )
    reload
    moved == 1
  end

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

  # Halon is told to repair it once, in the turn that first has room for it.
  def hand_back_noted! = claim(hand_back_noted_at: nil) { { hand_back_noted_at: Time.current } }

  # Handed back in this chat and not yet told to Halon, such as when the turn meant for it found a confirmation waiting.
  def self.hand_back_untold(chat)
    joins(:watch).where(chat_watches: { chat_id: chat.id }).where.not(handed_back_at: nil).where(hand_back_noted_at: nil).order(:handed_back_at)
  end

  # Waiting on a run that has not shown up since it could have, counted from when the watch began, the step before it
  # ended, or Halon last gave it a better read.
  def overdue?(now = Time.current)
    return false unless history? && status == STATUS_WAITING && handed_back_at.nil?

    earlier = watch.steps.select { |step| step.position < position }
    return false unless earlier.all?(&:over?)

    now - waiting_since(earlier) >= HAND_BACK_AFTER
  end

  def waiting_since(earlier = watch.steps.select { |step| step.position < position })
    [ watch.created_at, repaired_at, *earlier.filter_map(&:finished_at) ].compact.max
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
  # read is false when nothing was read, such as when the provider did not answer, so when it was last read stays true.
  # A reading that changed starts its steady time over.
  def seen!(digest:, state:, read: true, now: Time.current)
    changed = digest != last_digest
    update_columns(
      last_digest: digest, last_state: state.to_s.truncate(STATE_LIMIT), updated_at: now,
      **(read ? { read_at: now, steady_since: (changed || steady_since.nil? ? now : steady_since) } : {})
    )
  end

  def judged!(now = Time.current) = update_columns(judged_at: now)

  # The page of what it follows, from a reading that held one, kept from the first reading that did.
  def linked!(url)
    update_columns(run_url: url) if url.present? && run_url.blank?
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
