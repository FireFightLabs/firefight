# Something Halon was asked to follow and report on later, such as a release run and the deploy after it. It only ever
# reads, through the capabilities, as the person who asked and with exactly their permissions. Each step is checked
# about every minute (WatchSweepJob), or at once when a connection it reads says something changed. Every move is one
# guarded update, so two workers or a restart never report a milestone twice.
class Chat::Watch < ApplicationRecord
  STATUS_ACTIVE = "active"
  STATUS_SUCCEEDED = "succeeded"
  STATUS_FAILED = "failed"
  STATUS_TIMED_OUT = "timed_out"
  STATUS_STOPPED = "stopped"
  STATUSES = [ STATUS_ACTIVE, STATUS_SUCCEEDED, STATUS_FAILED, STATUS_TIMED_OUT, STATUS_STOPPED ].freeze
  ENDED = STATUSES - [ STATUS_ACTIVE ]

  # Where its time limit came from: the person asked, the provider's run history, Halon's memory, or nothing.
  BASIS_ASKED = "asked"
  BASIS_HISTORY = "history"
  BASIS_MEMORY = "memory"
  BASIS_DEFAULT = "default"
  # Moved later when steps were added, to leave them time to finish.
  BASIS_ADDED = "added"
  BASES = [ BASIS_ASKED, BASIS_HISTORY, BASIS_MEMORY, BASIS_DEFAULT, BASIS_ADDED ].freeze

  # Each watch reads its provider about once a minute, so a workspace keeps only so many going at once.
  ACTIVE_LIMIT = 20
  # What every read a watch makes is ledgered under.
  SOURCE = AbilityGateway::SOURCE_WATCH
  # At most this many steps are followed at once, and a watch that grows as steps are added keeps at most STEPS_IN_ALL.
  MAX_STEPS = 6
  STEPS_IN_ALL = 12
  LONGEST = 24.hours
  SHORTEST = 10.minutes
  DEFAULT_LIMIT = 60.minutes
  # A limit learned from how long it usually takes leaves this much room.
  BUFFER = 2
  CHECK_EVERY = 1.minute
  # A check that has not let go of its claim in this long belonged to a worker that died.
  CLAIM_LAPSES = 3.minutes
  OUTCOME_LIMIT = 2_000
  # Why the person wanted it, in their words, which every report measures what happened against.
  PURPOSE_LIMIT = 500
  TITLE_LIMIT = 120

  # How often a watch may call its providers, so it never runs into a provider's rate limit or runs up its cost. A watch
  # reads each step about once a minute, which this leaves room for twice over, and Halon may set it lower when a
  # provider's documented limit is tighter. Checks are spaced so the reads spread across the hour.
  READS_PER_STEP = 120
  FEWEST_READS = 6
  MOST_READS = 720
  HOUR = 1.hour

  # The keys of a start_watch request, which a runbook's watch is saved as and the runbook editor writes.
  SPEC_KEYS = {
    title: "title", minutes: "minutes", steps: "steps", label: "label", capability: "capability", resource: "resource",
    name: "name", run: "run", report_start: "report_start", done_when: "done_when", failed_when: "failed_when", goal: "goal",
    tool: "tool", focus: "focus", arguments: "arguments", new_deploy: "new_deploy", waits_for: "waits_for"
  }.freeze

  belongs_to :chat
  belongs_to :workspace
  # A person, a service key or an agent, whoever asked. Every read runs as them.
  belongs_to :asker, polymorphic: true
  belongs_to :stopped_by, class_name: "WorkspaceMembership", optional: true
  has_many :steps, -> { order(:position) }, class_name: "Chat::Watch::Step", dependent: :delete_all, inverse_of: :watch
  has_many :updates, -> { order(:created_at, :id) }, class_name: "Chat::Watch::Update", dependent: :delete_all, inverse_of: :watch

  validates :status, inclusion: { in: STATUSES }
  validates :limit_basis, inclusion: { in: BASES }

  scope :active, -> { where(status: STATUS_ACTIVE) }
  scope :not_checked_within, ->(duration) { where("checked_at IS NULL OR checked_at < ?", duration.ago) }
  scope :untold, -> { where(status: ENDED, told_at: nil) }
  # The watches going in a chat that this asker started, which steps on the same subject join rather than start another.
  scope :going_for, ->(asker) { active.where(asker: asker) }
  # Active, not checked within the last minute and not held back to keep under its ceiling, or held by a worker that died.
  scope :due, lambda { |now = Time.current|
    active.where("checked_at IS NULL OR checked_at <= ?", now - CHECK_EVERY + 5.seconds).where("next_check_at IS NULL OR next_check_at <= ?", now)
  }

  def conversation = chat.owner

  def active? = status == STATUS_ACTIVE

  def asker_name = asker.try(:display_name) || asker.try(:name) || "the person who asked"

  def limit_minutes = ((expires_at - created_at) / 60).round

  # How many reads an hour a watch of this many steps keeps to. Halon's number when it gave one, otherwise READS_PER_STEP for each.
  def self.ceiling_for(asked, steps)
    wanted = asked.to_i.positive? ? asked.to_i : READS_PER_STEP * steps.to_i
    wanted.clamp(FEWEST_READS, MOST_READS)
  end

  # Reads left in the hour that is running, all of them once that hour is over, within this ceiling.
  def reads_left(now = Time.current, ceiling: reads_per_hour)
    return ceiling if hour_over?(now)

    [ ceiling - reads_this_hour, 0 ].max
  end

  # The ceiling once this many steps join it. Halon's own number wins, a ceiling Halon set from a provider's limit is
  # kept, and otherwise it rises to the default for the steps still read, never falling.
  def ceiling_after_adding(asked, count)
    return self.class.ceiling_for(asked, count) if asked.to_i.positive?
    return reads_per_hour if reads_per_hour_asked?

    [ reads_per_hour, self.class.ceiling_for(nil, open_steps.size + count) ].max
  end

  def hour_over?(now = Time.current) = hour_began_at.nil? || hour_began_at <= now - HOUR

  # When the hour that is running ends, which is when a watch at its ceiling reads again.
  def hour_ends_at = (hour_began_at || Time.current) + HOUR

  # Counts the reads one check made and spaces the next check, so the hour's reads spread out rather than run out early.
  # Only the check holding the watch writes this, and the counts move in SQL so a stale row never undoes one.
  def count_reads!(count, now = Time.current)
    return if count.zero?

    fresh = hour_over?(now)
    # Within the minute the sweep keeps, the sweep's own rhythm is the spacing.
    spacing = count * HOUR.to_f / reads_per_hour
    self.class.where(id: id).update_all([
      "reads_total = reads_total + :count, reads_this_hour = CASE WHEN :fresh THEN :count ELSE reads_this_hour + :count END, " \
      "hour_began_at = CASE WHEN :fresh THEN :now ELSE hour_began_at END, next_check_at = :next, updated_at = :now",
      { count: count, fresh: fresh, now: now, next: (now + spacing.seconds if spacing > CHECK_EVERY) }
    ])
    reload
  end

  # Holds the next check until the hour that is running ends. True once in that hour, for whoever says so.
  def wait_for_hour!(now = Time.current)
    self.class.where(id: id).update_all(next_check_at: hour_ends_at, updated_at: now)
    told = self.class.where(id: id).where("ceiling_told_at IS NULL OR ceiling_told_at < ?", hour_began_at || now).update_all(ceiling_told_at: now)
    reload
    told == 1
  end

  # Takes the watch for one check. False when another worker holds it or it already ended.
  def claim_check!(now = Time.current)
    claimed = self.class.where(id: id, status: STATUS_ACTIVE)
                        .where("check_claimed_at IS NULL OR check_claimed_at < ?", now - CLAIM_LAPSES)
                        .update_all(check_claimed_at: now)
    claimed == 1
  end

  def release_check!(now = Time.current)
    self.class.where(id: id).update_all(check_claimed_at: nil, checked_at: now)
  end

  ANY_ADDED = Object.new.freeze

  # Ends it once, from active, so the outcome is said once however many workers reach it. False when it had ended.
  # steps_added_at is when steps were last added as the caller read them, so an end decided over the old steps never
  # lands once more were added. expired_by ends it only while its limit is still past, which adding steps can move.
  def finish!(status, outcome:, stopped_by: nil, steps_added_at: ANY_ADDED, expired_by: nil)
    scope = self.class.where(id: id, status: STATUS_ACTIVE)
    scope = scope.where(steps_added_at: steps_added_at) unless steps_added_at == ANY_ADDED
    scope = scope.where(expires_at: ..expired_by) if expired_by
    moved = scope.update_all(status: status, outcome: outcome.to_s.truncate(OUTCOME_LIMIT), finished_at: Time.current,
                             stopped_by_id: stopped_by&.id, updated_at: Time.current)
    reload
    moved == 1
  end

  # Ended on a reading shown to be wrong, so it goes again until until_at. A watch a person stopped stays stopped. False
  # when it was not one that ended on its own.
  REOPENABLE = [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_TIMED_OUT ].freeze

  def reopen!(until_at, now: Time.current)
    moved = self.class.where(id: id, status: REOPENABLE).update_all(
      status: STATUS_ACTIVE, outcome: nil, finished_at: nil, told_at: nil, expires_at: until_at, check_claimed_at: nil, next_check_at: nil, updated_at: now
    )
    reload
    moved == 1
  end

  # Until when a reopened watch goes: its whole limit again from now, never past LONGEST from when it started and never
  # earlier than it had. Nil when that leaves no time at all.
  def reopened_until(now = Time.current)
    until_at = [ [ now + (expires_at - created_at), expires_at ].max, created_at + LONGEST ].min
    until_at if until_at > now
  end

  # Moves the limit to minutes after it started, at most LONGEST, while it still goes. False when it had ended.
  def extend_to!(minutes)
    until_at = created_at + [ minutes.to_i.minutes, LONGEST ].min
    moved = self.class.where(id: id, status: STATUS_ACTIVE).update_all(expires_at: until_at, limit_basis: BASIS_ASKED, updated_at: Time.current)
    reload
    moved == 1
  end

  # Adds steps after the ones it has while it still goes, with their attributes, moving its limit to until_at when that
  # is later and its ceiling to reads_per_hour. The guarded update holds the watch's row until the steps are in, so a
  # check that read the old steps cannot end it meanwhile. False when it had ended.
  def add_steps!(attributes, until_at:, reads_per_hour:, title: nil, purpose: nil, now: Time.current)
    added = self.class.transaction do
      moved = self.class.where(id: id, status: STATUS_ACTIVE).update_all([
        "limit_basis = CASE WHEN expires_at < :until THEN :added ELSE limit_basis END, expires_at = GREATEST(expires_at, :until), " \
        "reads_per_hour = :ceiling, title = COALESCE(:title, title), purpose = COALESCE(:purpose, purpose), steps_added_at = :now, updated_at = :now",
        { until: until_at, added: BASIS_ADDED, ceiling: reads_per_hour, title: title&.truncate(TITLE_LIMIT), purpose: purpose&.truncate(PURPOSE_LIMIT), now: now }
      ])
      raise ActiveRecord::Rollback unless moved == 1

      after = Chat::Watch::Step.where(watch_id: id).maximum(:position).to_i
      attributes.each_with_index { |step, index| Chat::Watch::Step.create!(watch_id: id, position: after + 1 + index, added_at: now, **step) }
      true
    end
    reload
    added == true
  end

  NOTHING_TO_STOP = "This watch has already ended.".freeze

  # Why these steps cannot join it, or nil. Every read a watch makes runs as whoever started it, so only they add to it.
  def add_blocked_reason(asker, count)
    return "#{Chat::Watch::Shown.name(self)} has already ended, so start a new watch for these steps." unless active?
    return "Only #{asker_name} can add steps to #{Chat::Watch::Shown.named(self)}, since it reads as them. Start a separate watch." unless self.asker == asker
    if open_steps.size + count > MAX_STEPS
      return "#{Chat::Watch::Shown.name(self)} already follows #{open_steps.size} #{'step'.pluralize(open_steps.size)}, and a watch follows at most " \
             "#{MAX_STEPS} at once. Add the ones that matter most."
    end
    return "#{Chat::Watch::Shown.name(self)} already has #{steps.size} steps, and a watch keeps at most #{STEPS_IN_ALL}." if steps.size + count > STEPS_IN_ALL

    nil
  end

  # Whoever asked may stop it. In a channel or thread anyone there may too, since the asker may be away while it runs
  # on. A personal chat is its owner's alone.
  def stop_blocked_reason(member)
    return NOTHING_TO_STOP unless active?
    return if asker == member || in_shared_place?(member) || conversation.try(:started_by) == member

    "Only #{asker_name} or whoever this chat belongs to can stop this watch."
  end

  def in_shared_place?(member)
    member.is_a?(WorkspaceMembership) && member.workspace_id == workspace_id && conversation.try(:kind) == Conversation::KIND_CHANNEL
  end

  # The steps that are not over yet.
  def open_steps = steps.reject(&:over?)

  # The time limit and where it came from, for a workspace about to start one. Asked minutes win, then twice the usual
  # duration from run history, then twice what Halon remembers, then the default, each between SHORTEST and LONGEST.
  Limit = Data.define(:seconds, :basis, :usual_seconds)

  def self.limit_for(asked_minutes:, usual_seconds:, remembered_minutes:)
    if asked_minutes.to_i.positive?
      return Limit.new(seconds: [ asked_minutes.to_i.minutes, LONGEST ].min.to_i, basis: BASIS_ASKED, usual_seconds: usual_seconds)
    end
    return Limit.new(seconds: room_for(usual_seconds), basis: BASIS_HISTORY, usual_seconds: usual_seconds) if usual_seconds.to_i.positive?
    if remembered_minutes.to_i.positive?
      usual = remembered_minutes.to_i.minutes.to_i
      return Limit.new(seconds: room_for(usual), basis: BASIS_MEMORY, usual_seconds: usual)
    end

    Limit.new(seconds: DEFAULT_LIMIT.to_i, basis: BASIS_DEFAULT, usual_seconds: nil)
  end

  # Twice the usual, rounded up to whole five minutes, so a person reads "up to 40" rather than "up to 37".
  def self.room_for(usual_seconds)
    doubled = usual_seconds.to_i * BUFFER
    rounded = (doubled / 300.0).ceil * 300
    rounded.clamp(SHORTEST.to_i, LONGEST.to_i)
  end

  # Over the cap, the sentence Halon says. nil when there is room.
  def self.full_reason(workspace)
    return if workspace_active(workspace).count < ACTIVE_LIMIT

    "This workspace already has #{ACTIVE_LIMIT} watches going, which is as many as it keeps at once. Stop one first."
  end

  def self.workspace_active(workspace) = active.where(workspace_id: workspace.id)

  # The active watches with a step that reads through this connection, which a live update wakes at once.
  def self.reading_through(environment_row)
    active.where(id: Chat::Watch::Step.where(integration_environment_id: environment_row.id).select(:watch_id))
  end
end
