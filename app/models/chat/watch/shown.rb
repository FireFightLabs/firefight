# How a watch reads on its card, in the chat and over MCP, worked out once so every place says the same.
module Chat::Watch::Shown
  STEP_WORDS = {
    Chat::Watch::Step::STATUS_WAITING => "Waiting for it to start", Chat::Watch::Step::STATUS_RUNNING => "Running",
    Chat::Watch::Step::STATUS_SUCCEEDED => "Succeeded", Chat::Watch::Step::STATUS_FAILED => "Failed",
    Chat::Watch::Step::STATUS_UNFOLLOWABLE => "No longer followed"
  }.freeze
  ENDED = {
    Chat::Watch::STATUS_SUCCEEDED => "Done: %s", Chat::Watch::STATUS_FAILED => "Failed: %s", Chat::Watch::STATUS_TIMED_OUT => "Time limit reached: %s",
    Chat::Watch::STATUS_STOPPED => "Stopped watching: %s"
  }.freeze

  module_function

  # "40 min" within the hour, "2 hr 30 min" beyond.
  def limit_label(watch)
    hours, minutes = watch.limit_minutes.divmod(60)
    [ (hours.positive? ? "#{hours} hr" : nil), (minutes.positive? || hours.zero? ? "#{minutes} min" : nil) ].compact.join(" ")
  end

  def ended_headline(watch) = format(ENDED.fetch(watch.status), watch.title)

  # Such as "Watching: release run #46, up to 40 min" while it runs, and how it ended once it has.
  def headline(watch) = watch.active? ? "Watching: #{watch.title}, up to #{limit_label(watch)}" : ended_headline(watch)

  def basis(watch)
    usual = watch.usual_seconds && Integrations::Capabilities::History.duration(watch.usual_seconds)
    case watch.limit_basis
    when Chat::Watch::BASIS_ASKED then "Watching as long as #{watch.asker_name} asked."
    when Chat::Watch::BASIS_HISTORY then "It usually takes about #{usual}."
    when Chat::Watch::BASIS_MEMORY then "Halon remembers it taking about #{usual}."
    else "No history of how long it takes, so Halon watches for #{Integrations::Capabilities::History.duration(Chat::Watch::DEFAULT_LIMIT.to_i)}."
    end
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

  # What went on inside a step still going: the job or step that failed, otherwise what passed so far.
  def running_detail(step)
    return "#{step.failed_part} failed." if step.failed_part.present?

    passed = step.parts_passed
    "Passed so far: #{passed.join(', ')}." if passed.any?
  end

  # The watch for an outside agent over MCP, and for Halon's own list.
  def summary(watch)
    {
      id: watch.id, title: watch.title, purpose: watch.purpose, status: watch.status, started_at: watch.created_at.utc.iso8601, expires_at: watch.expires_at.utc.iso8601,
      limit: limit_label(watch), basis: basis(watch), outcome: watch.outcome,
      steps: watch.steps.map { |step| { label: step.label, status: step_status(step), state: step_state(step), last_seen: step.last_state&.truncate(300) } },
      said: watch.updates.map { |update| { at: update.created_at.utc.iso8601, text: update.text } }
    }
  end
end
