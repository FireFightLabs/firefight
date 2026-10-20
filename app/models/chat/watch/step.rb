# One thing a watch follows, read through one capability as the person who asked: a run in a resource's history (a CI
# run, a build, a deploy), or a reading such as a resource's status that says when it is done or failed. Each milestone
# is claimed by one guarded update, so it is reported once.
class Chat::Watch::Step < ApplicationRecord
  include NewDeploy
  include Order

  STATUS_WAITING = "waiting"
  STATUS_RUNNING = "running"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  # It could not be read any more, such as a permission taken away, so the watch no longer follows it.
  STATUS_UNFOLLOWABLE = "unfollowable"
  # Its read found nothing to follow, so Halon is picking a better one for it with repair_watch. It is not read meanwhile.
  STATUS_REPAIRING = "repairing"
  # A step it waits for failed or could not be followed, so it was never read. Not a failure of its own.
  STATUS_SKIPPED = "skipped"
  STATUSES = [ STATUS_WAITING, STATUS_RUNNING, STATUS_REPAIRING, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE, STATUS_SKIPPED ].freeze
  OVER = [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_UNFOLLOWABLE, STATUS_SKIPPED ].freeze
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
  # The readings that changed, newest last, kept so done and failed are judged over how a reading moved rather than one
  # reading on its own.
  READINGS_KEPT = 5
  READING_LIMIT = 8_000
  READING_AT = "at"
  READING_TEXT = "text"
  # How long a read usually takes to reach done, learned from this many of the same read that finished before.
  USUAL_FROM = 5
  SUMMARY_LIMIT = 200
  # Numbers and ids change from one run to the next, so the same read of a newer run counts as the same read.
  CHANGING_PART = /\b(?=[0-9a-f-]*\d)[0-9a-f]{6,}(?:-[0-9a-f]+)*\b|\d+/i

  # How a job or step inside what it follows stands, in the words its progress is said in.
  PART_WAITING = "waiting"
  PART_RUNNING = "running"
  PART_PASSED = "passed"
  PART_FAILED = "failed"
  # Starting and passing are said as progress. A failed job inside a run or a reading is said on its own with why.
  PART_SAID = [ PART_RUNNING, PART_PASSED ].freeze

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
  # What a read is the same as, kept as a digest so its usual time can be learned from the same read before: the tool or
  # capability with its arguments, numbers and ids left out.
  def self.signature(read_name, arguments)
    given = arguments.to_h.deep_stringify_keys.sort.to_h
    Digest::SHA256.hexdigest([ read_name.to_s, given.to_json.gsub(CHANGING_PART, "#") ].join("|"))
  end

  FOCUS_PATH = /\A[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*\z/
  JSON_START = /[\[{]/

  # The part of a reading a watch judges. With a focus, a path into the JSON the answer holds such as data.status or
  # data.nodes, only that part. Otherwise the whole reading, and one too long to judge keeps its start, where a run says
  # how it stands, and its end, where a later job or step that failed is listed.
  def self.focused(text, focus, limit = READING_LIMIT)
    picked = focus.present? ? at_path(text, focus) : nil
    text = picked ? "#{focus}: #{picked}" : text.to_s
    return text if text.length <= limit

    head = limit / 3
    tail = limit - head
    "#{text[0, head]}\n[... #{text.length - limit} characters between here and the end were left out ...]\n#{text[-tail..]}"
  end

  # The value at a dotted path in the first JSON value the text holds, as JSON, or nil when there is none there.
  def self.at_path(text, path)
    parsed = first_json(text.to_s)
    return if parsed.nil? || !path.to_s.match?(FOCUS_PATH)

    value = path.split(".").reduce(parsed) do |inner, key|
      case inner
      when Hash then inner.fetch(key) { return nil }
      when Array then key.match?(/\A\d+\z/) ? inner.fetch(key.to_i) { return nil } : inner.map { |item| item.is_a?(Hash) ? item[key] : nil }
      else return nil
      end
    end
    value.is_a?(String) ? value : JSON.generate(value)
  end

  # A provider's answer may lead with a line such as "Northflank answered GET ..." and end with a link, so the JSON is
  # what runs from its first bracket to one of its last closing ones.
  def self.first_json(text)
    start = text.index(JSON_START)
    return unless start

    ends = text.enum_for(:scan, /[\]}]/).map { Regexp.last_match.begin(0) }.last(5).reverse
    ends.each do |stop|
      return JSON.parse(text[start..stop])
    rescue JSON::ParserError
      next
    end
    nil
  end

  # How long the same read usually took to reach done in this workspace, the middle of the newest that did, or nil.
  def self.usual_for(workspace, signature)
    return if signature.blank?

    took = joins(:watch).where(chat_watches: { workspace_id: workspace.id }, read_signature: signature, status: STATUS_SUCCEEDED)
                        .where.not(started_at: nil).where.not(finished_at: nil).order(finished_at: :desc).limit(USUAL_FROM)
                        .pluck(:started_at, :finished_at).map { |started, finished| (finished - started).round }.select(&:positive?).sort
    return if took.empty?

    middle = took.size / 2
    took.size.odd? ? took[middle] : ((took[middle - 1] + took[middle]) / 2.0).round
  end

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

  # Its reading has not changed, and was not judged within JUDGE_STEADY_EVERY, so it is judged again. A reading that
  # showed it failed is always judged again, since the next reading confirms it or clears it.
  def judge_again?(now = Time.current) = judged_at.nil? || failure_seen_at.present? || now - judged_at >= JUDGE_STEADY_EVERY

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

  # The read it makes, as a repair compares it: what it reads with, its arguments and the run it names.
  def read_attributes = { capability: capability, tool_name: tool_name, arguments: arguments, run_name: run_name, run_ref: run_ref, focus: focus }

  # Follows it with another read from here on, starting over as if the watch began now. Only while it is still open,
  # so a step that ended meanwhile keeps its end. False when it had ended.
  def repaired!(read)
    moved = self.class.where(id: id, status: OPEN).update_all(
      **read, status: STATUS_WAITING, repairs: Arel.sql("repairs + 1"), repaired_at: Time.current, repair_reason: nil, handed_back_at: nil, hand_back_noted_at: nil,
              followed_run_id: nil, run_url: nil, started_at: nil, started_told_at: nil, slow_told_at: nil, failed_part: nil,
              failed_part_told_at: nil, parts_told: {}, last_digest: nil, last_state: nil, judged_at: nil, steady_since: nil, read_at: nil,
              readings: [], summary: nil, failure_seen_at: nil, sources_before: nil, updated_at: Time.current
    )
    reload
    moved == 1
  end

  # Follows it again from the start after it ended, with read when given, since its ending was shown to be wrong. Only
  # from an end, so a step still going is repaired instead. False when it had not ended.
  def reopened!(read = {})
    moved = self.class.where(id: id, status: OVER).update_all(
      **read, status: STATUS_WAITING, reason: nil, finished_at: nil, finished_told_at: nil, repaired_at: Time.current, repair_reason: nil,
              handed_back_at: nil, hand_back_noted_at: nil, followed_run_id: nil, run_url: nil, started_at: nil, started_told_at: nil,
              slow_told_at: nil, failed_part: nil, failed_part_told_at: nil, parts_told: {}, last_digest: nil, last_state: nil, judged_at: nil,
              steady_since: nil, read_at: nil, readings: [], summary: nil, failure_seen_at: nil, sources_before: nil, updated_at: Time.current
    )
    reload
    moved == 1
  end

  # A reading showed it failed, which the next reading confirms before it ends. True once, for whoever saw it first.
  def failure_seen!(now = Time.current) = claim(failure_seen_at: nil) { { failure_seen_at: now } }

  # The reading after one that showed it failed did not, so it goes on.
  def failure_cleared!
    update_columns(failure_seen_at: nil, updated_at: Time.current) if failure_seen_at
  end

  # When it began to be followed, which is when the watch started or when it was added to a watch already going.
  def begun_at = added_at || watch.created_at

  # The run this step follows among those a history read found: the one it already follows, the one the person named,
  # or the first of its name that started around or after the step began to be followed.
  # A step that waits for others follows only a run that started once they began, since it is the run they led to.
  def run_among(runs)
    return runs.find { |run| run.id.to_s == followed_run_id } if followed_run_id.present?
    return runs.find { |run| run.named?(run_ref) } if run_ref.present?

    since = waits? && runs_from ? runs_from - CLOCK_SLACK : begun_at - STARTED_BEFORE_WATCH
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

  # Waiting on a run that has not shown up since it could have, counted from when the step began to be followed, the
  # step before it ended, or Halon last gave it a better read. A step that waits for others could start only once they
  # all succeeded, so it counts from then, whatever else still goes.
  def overdue?(now = Time.current)
    return false unless (history? || read_tool?) && status == STATUS_WAITING && handed_back_at.nil?

    earlier = waits? ? prerequisites : watch.steps.select { |step| step.position < position }
    return false unless waits? ? ready? : earlier.all?(&:over?)

    now - waiting_since(earlier) >= HAND_BACK_AFTER
  end

  def waiting_since(earlier = waits? ? prerequisites : watch.steps.select { |step| step.position < position })
    [ begun_at, repaired_at, *earlier.filter_map(&:finished_at) ].compact.max
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
  # A reading that changed starts its steady time over, and a whole reading that changed is kept among its recent ones
  # when kept is true.
  def seen!(digest:, state:, read: true, now: Time.current, kept: false)
    changed = digest != last_digest
    recent = kept && read && changed ? (readings + [ { READING_AT => now.utc.iso8601, READING_TEXT => state.to_s.truncate(READING_LIMIT) } ]).last(READINGS_KEPT) : readings
    update_columns(
      last_digest: digest, last_state: state.to_s.truncate(STATE_LIMIT), readings: recent, updated_at: now,
      **(read ? { read_at: now, steady_since: (changed || steady_since.nil? ? now : steady_since) } : {})
    )
  end

  # The recent readings, oldest first, as pairs of when and what.
  def recent_readings = readings.map { |reading| [ Time.zone.parse(reading[READING_AT].to_s), reading[READING_TEXT].to_s ] }

  # Where it stands now in a few words, such as "build-images running, 4 of 7 done", for its row on the card.
  def summarized!(text)
    said = text.to_s.squish.truncate(SUMMARY_LIMIT).presence
    update_columns(summary: said) if said != summary
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

  def finished_before_watch?(run) = run.finished? && run.finished_at && run.finished_at < begun_at

  def claim(unset)
    moved = self.class.where(id: id, **unset).update_all(**yield, updated_at: Time.current)
    reload
    moved == 1
  end
end
