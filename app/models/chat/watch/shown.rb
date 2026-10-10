# How a watch reads on its card, in the chat and over MCP, worked out once so every place says the same. A watch is named
# for what it waits on, such as Watch "Deploy finished".
module Chat::Watch::Shown
  STEP_WORDS = {
    Chat::Watch::Step::STATUS_WAITING => "Waiting for it to start", Chat::Watch::Step::STATUS_RUNNING => "Running",
    Chat::Watch::Step::STATUS_REPAIRING => "Finding a better way to follow it",
    Chat::Watch::Step::STATUS_SUCCEEDED => "Succeeded", Chat::Watch::Step::STATUS_FAILED => "Failed",
    Chat::Watch::Step::STATUS_UNFOLLOWABLE => "No longer followed"
  }.freeze
  # A step's status within a sentence, such as "shows Deploy done, where it still had it not started".
  STEP_PHRASES = {
    Chat::Watch::Step::STATUS_WAITING => "not started", Chat::Watch::Step::STATUS_RUNNING => "running",
    Chat::Watch::Step::STATUS_REPAIRING => "being repaired", Chat::Watch::Step::STATUS_SUCCEEDED => "done",
    Chat::Watch::Step::STATUS_FAILED => "failed", Chat::Watch::Step::STATUS_UNFOLLOWABLE => "no longer followed"
  }.freeze
  ENDED = {
    Chat::Watch::STATUS_SUCCEEDED => "%s: done", Chat::Watch::STATUS_FAILED => "%s: failed", Chat::Watch::STATUS_TIMED_OUT => "%s: time limit reached",
    Chat::Watch::STATUS_STOPPED => "%s: stopped"
  }.freeze

  module_function

  # Such as Watch "Deploy finished", which starts a line.
  def name(watch) = %(Watch "#{watch.title}")

  # Such as the watch "Deploy finished", within a sentence.
  def named(watch) = %(the watch "#{watch.title}")

  # "40 min" within the hour, "2 hr 30 min" beyond.
  def limit_label(watch)
    hours, minutes = watch.limit_minutes.divmod(60)
    [ (hours.positive? ? "#{hours} hr" : nil), (minutes.positive? || hours.zero? ? "#{minutes} min" : nil) ].compact.join(" ")
  end

  def ended_headline(watch) = format(ENDED.fetch(watch.status), name(watch))

  # Its name while it runs, and how it ended once it has.
  def headline(watch) = watch.active? ? name(watch) : ended_headline(watch)

  # How long it watches and why, such as "Up to 40 min. It usually takes about 18 minutes."
  def basis(watch)
    usual = watch.usual_seconds && Integrations::Capabilities::History.duration(watch.usual_seconds)
    why = case watch.limit_basis
    when Chat::Watch::BASIS_ASKED then "Watching as long as #{watch.asker_name} asked."
    when Chat::Watch::BASIS_HISTORY then "It usually takes about #{usual}."
    when Chat::Watch::BASIS_MEMORY then "Halon remembers it taking about #{usual}."
    else "No history of how long it takes, so Halon watches for #{Integrations::Capabilities::History.duration(Chat::Watch::DEFAULT_LIMIT.to_i)}."
    end
    "Up to #{limit_label(watch)}. #{why}"
  end

  # Its ceiling on reads and how many it made, such as "Reads at most 120 times an hour. 14 reads so far."
  def reads(watch)
    "Reads at most #{watch.reads_per_hour} times an hour. #{watch.reads_total} #{'read'.pluralize(watch.reads_total)} so far."
  end

  # A step still open when its watch ended is no longer followed, whatever it last read.
  def step_status(step) = step.over? || step.watch.active? ? step.status : Chat::Watch::Step::STATUS_UNFOLLOWABLE

  # The step's status in words, with what the last read showed or why it failed.
  def step_state(step)
    unless step.over? || step.watch.active?
      return step.running? ? "Still running when the watch ended." : "Not started when the watch ended."
    end

    words = STEP_WORDS.fetch(step.status)
    detail = step.over? ? step.reason : running_detail(step)
    took = step.seconds_taken && step.status == Chat::Watch::Step::STATUS_SUCCEEDED ? " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}" : ""
    [ "#{words}#{took}.", detail.presence ].compact.join(" ")
  end

  # What went on inside a step still going. That is why it is being repaired, the job or step that failed, or otherwise
  # what passed so far.
  def running_detail(step)
    return step.repair_reason if step.repairing?
    return "#{step.failed_part} failed." if step.failed_part.present?

    passed = step.parts_passed
    "Passed so far: #{passed.join(', ')}." if passed.any?
  end

  # The page of the run or what a step follows, when the provider gave one.
  def link(watch) = watch.steps.reverse.find { |step| step.run_url.present? }&.run_url

  # The watch for an outside agent over MCP, and for Halon's own list. last_read is when each step was last read, so a
  # reader can tell a fresh state from a remembered one.
  def summary(watch)
    {
      id: watch.id, title: watch.title, name: name(watch), purpose: watch.purpose, status: watch.status, started_at: watch.created_at.utc.iso8601,
      expires_at: watch.expires_at.utc.iso8601, limit: limit_label(watch), basis: basis(watch), reads: reads(watch), outcome: watch.outcome,
      steps: watch.steps.map do |step|
        { label: step.label, reads_with: step.read_words, status: step_status(step), state: step_state(step), last_seen: step.last_state&.truncate(300),
          last_read: step.read_at&.utc&.iso8601, url: step.run_url }
      end,
      said: watch.updates.map { |update| { at: update.created_at.utc.iso8601, text: update.text } }
    }
  end
end
