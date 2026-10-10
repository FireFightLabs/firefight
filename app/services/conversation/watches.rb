# Watches from start to end. Halon writes one when a person asks to be told later, as keep reading this until that holds,
# with any read it may make. The sweep and live updates check it within a ceiling on reads. Each milestone and the end
# are said once, in the chat, in its thread when it has one, and in the asker's direct messages. A read that finds
# nothing to follow is handed back to Halon to repair, and a reading Halon takes in the chat overrides what the watch
# had. A watch only reads, as the person who asked.
module Conversation::Watches
  HISTORY = Integrations::Capabilities::HISTORY
  # How a job or step inside a run stands, in the words its progress is said in.
  PART_STATES = {
    Integrations::Capabilities::History::QUEUED => Chat::Watch::Step::PART_WAITING,
    Integrations::Capabilities::History::RUNNING => Chat::Watch::Step::PART_RUNNING,
    Integrations::Capabilities::History::SUCCEEDED => Chat::Watch::Step::PART_PASSED,
    Integrations::Capabilities::History::FAILED => Chat::Watch::Step::PART_FAILED,
    Integrations::Capabilities::History::CANCELLED => Chat::Watch::Step::PART_FAILED
  }.freeze
  READING_PARTS = {
    FirefightAi::Schemas::WatchReading::PART_WAITING => Chat::Watch::Step::PART_WAITING,
    FirefightAi::Schemas::WatchReading::PART_RUNNING => Chat::Watch::Step::PART_RUNNING,
    FirefightAi::Schemas::WatchReading::PART_PASSED => Chat::Watch::Step::PART_PASSED,
    FirefightAi::Schemas::WatchReading::PART_FAILED => Chat::Watch::Step::PART_FAILED
  }.freeze
  # A run's state the watch counts as a step's end.
  RUN_ENDS = {
    Integrations::Capabilities::History::SUCCEEDED => Chat::Watch::Step::STATUS_SUCCEEDED,
    Integrations::Capabilities::History::FAILED => Chat::Watch::Step::STATUS_FAILED,
    Integrations::Capabilities::History::CANCELLED => Chat::Watch::Step::STATUS_FAILED
  }.freeze
  # How much of a log a failure is explained from.
  LOG_LINES = 80
  EVIDENCE_LIMIT = 8_000
  # Times in a reading change every minute without anything changing, so they are left out of what counts as new.
  CLOCK = /\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?|\b\d+\s+(seconds?|minutes?|hours?)\s+ago\b/i

  # What the line on the card and the message say for each way a watch ends.
  TONE_DONE = "done".freeze
  TONE_FAILED = "failed".freeze
  TONE_TIMED_OUT = "timed_out".freeze
  TONE_STOPPED = "stopped".freeze
  ENDED_TONES = {
    Chat::Watch::STATUS_SUCCEEDED => TONE_DONE, Chat::Watch::STATUS_FAILED => TONE_FAILED, Chat::Watch::STATUS_TIMED_OUT => TONE_TIMED_OUT,
    Chat::Watch::STATUS_STOPPED => TONE_STOPPED
  }.freeze
  # A line's mark: its kind while the watch goes on, how it ended for the last one.
  TONES = [ *(Chat::Watch::Update::KINDS - [ Chat::Watch::Update::KIND_ENDED ]), *ENDED_TONES.values ].freeze

  # One line a watch said, as the chat, the platform's message and MCP show it. live is whether the watch still went
  # when it was said, which is when the platform's message offers Stop.
  # name is the watch named for what it waits on, link the page of what it follows when the provider gave one.
  Said = Data.define(:id, :watch_id, :title, :name, :kind, :tone, :text, :at, :live, :link) do
    def initialize(live: false, link: nil, **rest) = super
  end

  # Starts a watch for whoever asks this turn, and answers what Halon tells the person: how long it will watch and
  # why, and anything it cannot follow. arguments are start_watch's, with string keys.
  def self.start(turn, arguments)
    workspace = turn.workspace
    asker = turn.asker
    return "Nobody can be credited with this watch, so it was not started." unless asker

    full = Chat::Watch.full_reason(workspace)
    return full if full

    given = Array(arguments["steps"]).map { |step| step.to_h.transform_keys(&:to_s) }
    return "Say what to watch, as one or more steps, each naming a capability that reads and a resource." if given.empty?
    return "A watch follows at most #{Chat::Watch::MAX_STEPS} steps. Watch the ones that matter most." if given.size > Chat::Watch::MAX_STEPS

    ceiling = Chat::Watch.ceiling_for(arguments["reads_per_hour"], given.size)
    meter = Chat::Watch::Meter.new(ceiling)
    reader, agent = readers(workspace, asker, turn.conversation, meter)
    planned, cannot = plan(given, reader, agent)
    return "Nothing was started, since none of it can be followed. #{cannot.join(' ')}" if planned.empty?

    usual = planned.filter_map { |step| step[:usual] }.sum.nonzero?
    limit = Chat::Watch.limit_for(asked_minutes: arguments["minutes"], usual_seconds: usual, remembered_minutes: arguments["expected_minutes"])
    title = arguments["title"].to_s.strip.presence || planned.first[:label]
    watch = create!(turn, title, limit, planned, purpose: arguments["purpose"].to_s.strip.presence, reads_per_hour: ceiling)
    watch.count_reads!(meter.count)
    Conversation::LiveDelivery.watch_moved(turn.conversation)
    # Something that fails the moment it starts is told within seconds rather than at the next sweep.
    WatchCheckJob.perform_later(watch.id)

    [ "Started #{Chat::Watch::Shown.name(watch)}. Tell the person, in your own words: #{limit_sentence(limit)} " \
      "It reads at most #{ceiling} times an hour, which the card shows.",
      cannot.any? ? "Also tell them what it cannot follow: #{cannot.join(' ')}" : nil,
      "Each milestone and the end come to this chat and to their direct messages on their own, so never check it " \
      "again yourself unless they ask. When a step's read finds nothing to follow, it is handed back to you to repair " \
      "with repair_watch. It can be stopped from the chat or with stop_watch (watch #{watch.id})." ].compact.join("\n")
  end

  # The reads one watch makes, counted on one meter.
  def self.readers(workspace, asker, conversation, meter)
    [ Conversation::Watches::Reader.new(workspace: workspace, principal: asker, conversation: conversation, meter: meter),
      Conversation::Watches::Agent.new(workspace: workspace, asker: asker, conversation: conversation, meter: meter) ]
  end

  # Each step routed as the asker before anything is kept, history read once for how long it usually takes. A step that
  # names one of Halon's read tools is read once, so a tool it may not use or a read that fails is said now.
  def self.plan(given, reader, agent)
    planned = []
    cannot = []
    given.each_with_index do |step, index|
      label = step["label"].to_s.strip.presence || "Step #{index + 1}"
      next plan_tool_step(step, label, reader, agent, planned, cannot) if step["tool"].present?

      key = key_for(step["capability"])
      next cannot << "#{label} cannot be followed, since #{step['capability'].presence || 'it names no capability, and that'} is not a read a watch can make." unless key

      arguments = arguments_for(step, key)
      next cannot << "#{label} needs what counts as done for it (done_when, failed_when or goal)." if Chat::Watch::Step.undecided?(step)

      usual, row = first_read(reader, key, arguments, step)
      planned << { label: label, key: key, arguments: arguments, step: step, usual: usual, row: row }
    rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered => refused
      cannot << "#{label} cannot be followed. #{refused.message}"
    rescue Chat::Watch::Meter::Spent
      cannot << "#{label} was not read, since this watch's ceiling on reads for the hour is spent."
    end
    [ planned, cannot ]
  end

  def self.plan_tool_step(step, label, reader, agent, planned, cannot)
    return cannot << "#{label} needs what counts as done for it (done_when, failed_when or goal)." if Chat::Watch::Step.undecided?(step)

    arguments = step["arguments"].is_a?(Hash) ? step["arguments"].transform_keys(&:to_s).except(Chat::Tools::INTENT_ARG) : {}
    said = reader.read_tool(agent, step["tool"], arguments)
    return cannot << "#{label} cannot be followed, since reading it failed: #{Chat::SecretFree.redacted(said.text).truncate(300)}" if said.failed?

    planned << { label: label, key: Chat::Watch::Step::READ_TOOL, tool: step["tool"].to_s, arguments: arguments, step: step, usual: nil, row: nil }
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered => refused
    cannot << "#{label} cannot be followed. #{refused.message}"
  rescue Chat::Watch::Meter::Spent
    cannot << "#{label} was not read, since this watch's ceiling on reads for the hour is spent."
  end

  def self.first_read(reader, key, arguments, step)
    return [ nil, reader.route(key, arguments).environment_row ] unless key == HISTORY

    answer = reader.read(key, arguments)
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if runs.nil?

    [ Integrations::Capabilities::History.usual_seconds(runs, name: step["name"]), answer.call.environment_row ]
  end

  def self.create!(turn, title, limit, planned, purpose: nil, reads_per_hour: Chat::Watch.ceiling_for(nil, planned.size))
    Chat::Watch.transaction do
      watch = Chat::Watch.create!(
        chat: turn.conversation.chat_record, workspace: turn.workspace, asker: turn.asker, title: title.truncate(Chat::Watch::TITLE_LIMIT),
        purpose: purpose&.truncate(Chat::Watch::PURPOSE_LIMIT), reads_per_hour: reads_per_hour,
        expires_at: limit.seconds.seconds.from_now, usual_seconds: limit.usual_seconds, limit_basis: limit.basis
      )
      planned.each_with_index do |planned_step, position|
        watch.steps.create!(position: position, label: planned_step[:label].truncate(120), **read_of(planned_step))
      end
      watch
    end
  end

  # What a planned step reads and when it counts as over, as a step keeps it.
  def self.read_of(planned_step)
    given = planned_step[:step]
    {
      capability: planned_step[:key], arguments: planned_step[:arguments], tool_name: planned_step[:tool],
      integration_environment_id: planned_step[:row]&.id, run_name: given["name"].presence, run_ref: given["run"].presence,
      report_start: ActiveModel::Type::Boolean.new.cast(given["report_start"]) || false, done_when: given["done_when"].presence,
      failed_when: given["failed_when"].presence, goal: given["goal"].presence, usual_seconds: planned_step[:usual]
    }
  end

  def self.key_for(name) = Chat::Watch::Step.read_key(name)

  def self.arguments_for(step, key)
    extra = step["arguments"].is_a?(Hash) ? step["arguments"].transform_keys(&:to_s) : {}
    named = { Integrations::Capabilities::RESOURCE_ARG => step["resource"], Integrations::Capabilities::CONNECTION_ARG => step["connection"] }
    named["name"] = step["name"] if key == HISTORY
    extra.merge(named.compact_blank).except(Chat::Tools::INTENT_ARG)
  end

  # How long it watches and why, as the person reads it: "This usually takes about 18 minutes, I will watch for up to 40."
  def self.limit_sentence(limit)
    up_to = limit_words(limit)
    usual = limit.usual_seconds && Integrations::Capabilities::History.duration(limit.usual_seconds)
    case limit.basis
    when Chat::Watch::BASIS_ASKED
      [ ("This usually takes about #{usual}." if usual), "I will watch for up to #{Integrations::Capabilities::History.duration(limit.seconds)}, as you asked." ].compact.join(" ")
    when Chat::Watch::BASIS_HISTORY then "This usually takes about #{usual}, I will watch for up to #{up_to}."
    when Chat::Watch::BASIS_MEMORY then "From what I remember this takes about #{usual}, so I will watch for up to #{up_to}."
    else "I have no history of how long this takes, so I will watch for up to #{Integrations::Capabilities::History.duration(limit.seconds)}. Ask me for longer if it needs it."
    end
  end

  # Within the hour the unit is the usual's, so it reads "up to 40".
  def self.limit_words(limit)
    words = Integrations::Capabilities::History.duration(limit.seconds)
    short = limit.seconds < 3600 && limit.usual_seconds.to_i.between?(90, 3599)
    short ? words.delete_suffix(" minutes") : words
  end

  # One check: each open step read once, its milestones said once, the jobs or steps that moved said together in one
  # line, and the watch ended when they are all over or its time ran out. A watch another worker holds is left to it.
  # Every read is counted against the watch's ceiling, and one past it waits for the next hour.
  def self.check!(watch, now: Time.current)
    return unless watch.active? && watch.claim_check!(now)

    meter = Chat::Watch::Meter.new(watch.reads_left(now))
    read_all = true
    begin
      return time_out!(watch) if now >= watch.expires_at

      progress = []
      read_all = read_steps(watch, watch.open_steps, meter, now, progress)
      tell!(watch, Chat::Watch::Update::KIND_PROGRESS, progress.join("\n")) if progress.any?
      conclude!(watch)
    ensure
      settle_reads!(watch, meter, now, read_all: read_all)
    end
  end

  # Reads each step until the ceiling stops it. False when it did. reading is what Halon already read in its chat for
  # these steps, used in place of reading it again.
  def self.read_steps(watch, steps, meter, now, progress, reading: nil)
    reader, agent = readers(watch.workspace, watch.asker, watch.conversation, meter)
    steps.each { |step| check_step(watch, step, reader, agent, now, progress, reading: reading) }
    true
  rescue Chat::Watch::Meter::Spent
    false
  end

  # Counts what a check read and lets the watch go. One stopped by its ceiling waits for the hour to end, said once
  # that hour.
  def self.settle_reads!(watch, meter, now, read_all:)
    watch.count_reads!(meter.count, now)
    tell!(watch, Chat::Watch::Update::KIND_CEILING, ceiling_words(watch, now)) if !read_all && watch.active? && watch.wait_for_hour!(now)
  ensure
    watch.release_check!
  end

  def self.ceiling_words(watch, now)
    wait = Integrations::Capabilities::History.duration([ watch.hour_ends_at - now, 60 ].max)
    "#{Chat::Watch::Shown.name(watch)} made the #{watch.reads_per_hour} reads it allows itself an hour, so it reads again in #{wait}."
  end

  def self.check_step(watch, step, reader, agent, now, progress, reading: nil)
    return repair_lapsed!(watch, step) if step.repair_overdue?(now)
    return if step.repairing?
    return follow_run(watch, step, reader, now, progress) if step.history?
    return take_reading(watch, step, reading, progress, now: now) if reading

    follow_reading(watch, step, reader, agent, progress, now: now)
  rescue Conversation::Watches::Reader::Unanswered => unanswered
    step.seen!(digest: step.last_digest, state: "Could not read it just now: #{unanswered.message}", read: false)
  rescue Conversation::Watches::Reader::Refused => refused
    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "I can no longer follow #{step.label}. #{refused.message}") if step.unfollowable!(refused.message)
  end

  # A run already found, or the one the person or Halon named, is read by its id, which brings its jobs or steps where
  # the provider breaks a run down. Only a step with no run named looks through the list of recent runs.
  def self.follow_run(watch, step, reader, now, progress)
    answer, runs = exact_run(step, reader) || listed_runs(step, reader)
    run = step.run_among(runs)
    unless run
      step.seen!(digest: nil, state: "No run of #{step.label} has started yet.")
      return hand_back!(watch, step, runs, now) if step.overdue?(now)

      return
    end

    detailed = detailed(run, answer.call.environment_row, step, reader)
    run = detailed.run
    step.seen!(digest: run.status, state: Integrations::Capabilities::History.line(run))
    moved = step.progress!(Array(run.parts).map { |part| [ part.name.to_s, PART_STATES.fetch(part.status, Chat::Watch::Step::PART_WAITING) ] })
    progress << "#{step.label}: #{moved.join(', ')}." if moved.any? && !run.finished?
    tell_failed_part(watch, step, run, detailed.environment_row, reader)
    unless run.finished?
      said_start = step.started_told_at.nil? && step.started!(run_id: run.id.to_s, at: run.started_at, url: run.url)
      tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} started.") if said_start && step.report_start
      tell!(watch, Chat::Watch::Update::KIND_SLOW, slow_words(step, now)) if step.slow?(now) && step.slow_told!
      return
    end

    ended = RUN_ENDS.fetch(run.status)
    reason = why_failed(watch, step, run, reader, answer.call, environment_row: detailed.environment_row) if ended == Chat::Watch::Step::STATUS_FAILED
    return unless step.finished!(ended, reason: reason, at: run.finished_at, run_id: run.id.to_s, url: run.url, started: run.started_at)

    took = step.seconds_taken && " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}"
    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, standing(watch, "#{step.label} succeeded#{took}.")) if ended == Chat::Watch::Step::STATUS_SUCCEEDED
  end

  # The run read by the id the step follows or was given, nil when there is none or the provider finds no run by it.
  def self.exact_run(step, reader)
    id = step.followed_run_id.presence || step.run_ref.presence
    return unless id

    answer = reader.read(HISTORY, step.arguments.merge(RUN_ARG => id))
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    return [ answer, runs ] if step.followed_run_id.present? || runs&.any? { |run| run.named?(id) }

    nil
  rescue Conversation::Watches::Reader::Unanswered
    raise if step.followed_run_id.present?
  end

  def self.listed_runs(step, reader)
    answer = reader.read(HISTORY, step.arguments)
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if runs.nil?

    [ answer, runs ]
  end

  # A run read again by its id, with its jobs or steps, where the provider's history breaks a run down. One the provider
  # cannot read that way is the run as the list gave it.
  Detailed = Data.define(:run, :environment_row)

  def self.detailed(run, environment_row, step, reader)
    listed = Detailed.new(run: run, environment_row: environment_row)
    return listed if run.parts || run.id.blank?

    call = reader.route(HISTORY, step.arguments.merge(RUN_ARG => run.id.to_s))
    return listed unless call.arguments.value?(run.id.to_s)

    answer = reader.read_call(call)
    found = Integrations::Capabilities::History.runs_of(answer.result)&.find { |each| each.id.to_s == run.id.to_s }
    found ? Detailed.new(run: found, environment_row: answer.call.environment_row) : listed
  rescue Conversation::Watches::Reader::Unanswered
    listed
  end

  # The first job or step that failed is said at once, with why from its own log, while the run still goes.
  def self.tell_failed_part(watch, step, run, environment_row, reader)
    part = run.first_failed_part
    return unless part && step.failed_part_told_at.nil? && step.part_failed!(part.name)

    took = part.seconds && ", #{Integrations::Capabilities::History.duration(part.seconds)} in"
    why = part_reason(watch, step, part, environment_row, reader)
    words = "#{step.label}: #{part.name} failed#{" #{part.detail}" if part.detail.present?}#{took}. #{why} #{part.url}".squish
    tell!(watch, Chat::Watch::Update::KIND_PART_FAILED, standing(watch, words))
  end

  def self.part_reason(watch, step, part, environment_row, reader)
    lines = part_log(part, environment_row, reader)
    return "It did not say why." if lines.blank?

    explained = judge(watch)&.why_failed(what: "#{step.label}, #{part.name}", evidence: [ part.detail, lines ].compact.join("\n").truncate(EVIDENCE_LIMIT))
    explained.presence || error_lines(lines) || "It did not say why."
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::OutOfCredit
    error_lines(lines) || "It did not say why."
  end

  def self.part_log(part, environment_row, reader)
    return if part.log.blank? || environment_row.nil?

    answer = reader.read_log(environment_row, part.log)
    answer.failed? ? nil : Chat::SecretFree.redacted(answer.text).lines.last(LOG_LINES).join
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered
    nil
  end

  # No run showed up where one was expected, so Halon is asked to repair the step with a better read.
  def self.hand_back!(watch, step, runs, now)
    waited = Integrations::Capabilities::History.duration(now - step.waiting_since)
    latest = runs.first(3).map { |run| Integrations::Capabilities::History.line(run) }.join("\n")
    Rails.logger.info({ event: "watch.handed_back", watch_id: watch.id, step_id: step.id, latest: latest.truncate(300) }.to_json)
    ask_repair!(watch, step, "I could not find a run of #{step.label} in its history after #{waited}.")
  end

  RUN_ARG = "run".freeze

  # A step whose read found nothing to follow is never left following nothing. The person is told, and Halon is asked to
  # repair it with a better read, in the chat the watch was started from, in a turn that only reads. One Halon already
  # repaired MAX_REPAIRS times is no longer followed instead.
  def self.ask_repair!(watch, step, reason)
    unless step.repairable?
      gave_up = "#{reason} No read Halon tried could show it."
      tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "I stopped following #{step.label}. #{gave_up}") if step.unfollowable!(gave_up)
      return
    end
    return unless step.repair_asked!(reason)

    tell!(watch, Chat::Watch::Update::KIND_HANDED_BACK, "#{reason} I am finding a better way to follow #{step.label}.")
    ConversationReplyJob.perform_later(watch.conversation.id, (watch.asker.id if watch.asker.is_a?(WorkspaceMembership)), nil, step.id)
  end

  # Halon did not repair it in time, such as while the chat waited on the person.
  def self.repair_lapsed!(watch, step)
    lapsed = "No better read was found for it within #{Integrations::Capabilities::History.duration(Chat::Watch::Step::REPAIR_WITHIN.to_i)}."
    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "I stopped following #{step.label}. #{lapsed}") if step.unfollowable!(lapsed)
  end

  # What Halon reads when a step is handed back. It says what the read found and why the person wanted it, and asks
  # Halon to repair the step in place by reading, never by changing anything.
  def self.hand_back_note(step)
    watch = step.watch
    [
      "#{Chat::Watch::Shown.name(watch)} (watch #{watch.id}) found nothing to follow for its step #{step.label}, read with #{step.read_words} " \
      "(#{step.arguments.except(Chat::Tools::INTENT_ARG).to_json}).",
      step.repair_reason.presence,
      ("It was started for: #{watch.purpose}" if watch.purpose.present?),
      "Find a read that shows it with the provider's read tools, its skill or search_docs, such as a GET request for that one run by its id, " \
      "and try it once. Then call repair_watch with this watch and step, the new read and why the old one showed nothing, so the same watch " \
      "follows it from here. When no read can show it, call repair_watch with give_up. Change nothing in this turn. Tell the person in a " \
      "sentence or two what you changed, or what you could not find."
    ].compact.join(" ")
  end

  # Halon gives an open step a better read, so the same watch follows it from here and says what changed. given is a
  # start_watch step with string keys, whose done and failed words default to the step's own. Answers what Halon tells
  # the person. The new read is tried as the watch's own asker, whom every later check reads as.
  def self.repair!(watch, step, given, why:)
    return Chat::Watch::NOTHING_TO_STOP unless watch.active?
    return "#{step.label} has already ended, so there is nothing to repair." unless Chat::Watch::Step::OPEN.include?(step.status)
    return give_up!(watch, step, why) if ActiveModel::Type::Boolean.new.cast(given["give_up"])
    return "#{step.label} was repaired #{Chat::Watch::Step::MAX_REPAIRS} times already. Call repair_watch with give_up instead." unless step.repairable?

    kept = { "done_when" => step.done_when, "failed_when" => step.failed_when, "goal" => step.goal }.compact
    meter = Chat::Watch::Meter.new(watch.reads_left)
    reader, agent = readers(watch.workspace, watch.asker, watch.conversation, meter)
    planned, cannot = plan([ kept.merge(given.except("give_up")).merge("label" => step.label) ], reader, agent)
    watch.count_reads!(meter.count)
    return "Not repaired. #{cannot.join(' ')}" if planned.empty?

    before = step.read_words
    return "#{step.label} has already ended, so there is nothing to repair." unless step.repaired!(read_of(planned.first))

    tell!(watch, Chat::Watch::Update::KIND_REPAIRED,
          "Changed how I follow #{step.label}: I now read #{step.read_words} instead of #{before}. #{why.to_s.strip.presence || 'The old read showed nothing to follow.'}")
    WatchCheckJob.perform_later(watch.id)
    "Repaired #{step.label} in #{Chat::Watch::Shown.named(watch)}. Tell the person in a sentence what you changed and why."
  end

  def self.give_up!(watch, step, why)
    reason = [ "Halon found no read that shows it.", why.to_s.strip.presence ].compact.join(" ")
    return "#{step.label} has already ended." unless step.unfollowable!(reason)

    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "I stopped following #{step.label}. #{reason}")
    conclude!(watch)
    "Stopped following #{step.label}. Tell the person in a sentence why."
  end

  def self.slow_words(step, now)
    so_far = Integrations::Capabilities::History.duration(now - step.started_at)
    "#{step.label} is taking longer than usual, #{so_far} so far where it usually takes #{Integrations::Capabilities::History.duration(step.usual_seconds)}."
  end

  # A reading that is not a run, read by the step's own read.
  def self.follow_reading(watch, step, reader, agent, progress, now: Time.current)
    answer = step.read_tool? ? reader.read_tool(agent, step.tool_name, step.arguments) : reader.read(step.capability, step.arguments)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if answer.failed?

    take_reading(watch, step, answer.text, progress, now: now)
  end

  # Done or failed by the words the watch was given, otherwise judged by a model against the condition in plain words,
  # into not started, running, done, failed or nothing to follow, with the jobs or steps it lists and its page. Each
  # reading that changed is judged, and one that stayed the same every JUDGE_STEADY_EVERY. A reading that shows it begun
  # moves the step to running, and a first reading with nothing to follow is handed back to Halon to repair.
  def self.take_reading(watch, step, text, progress, now: Time.current)
    text = Chat::SecretFree.redacted(text)
    digest = Digest::SHA256.hexdigest(text.gsub(CLOCK, ""))
    before = step.last_state
    changed = digest != step.last_digest
    step.seen!(digest: digest, state: text, now: now)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, excerpt(text, step.failed_when)) if says?(text, step.failed_when)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, nil) if says?(text, step.done_when)
    return unless changed || step.judge_again?(now)

    first = step.judged_at.nil? && step.status == Chat::Watch::Step::STATUS_WAITING
    judged = judge(watch)&.reading(goal: reading_goal(step), before: before, now: text.truncate(EVIDENCE_LIMIT),
                                   so_far: step.running? ? "running" : "not started", steady: steady_words(step, now))
    return unless judged

    step.judged!(now)
    step.linked!(judged.link)
    if judged.state == FirefightAi::Schemas::WatchReading::NOTHING
      return ask_repair!(watch, step, "The first reading of #{step.label} showed nothing to follow. #{judged.said}".strip) if first

      return
    end

    moved = step.progress!(judged.parts.filter_map { |name, state| [ name, READING_PARTS[state] ] if READING_PARTS[state] }, said: Chat::Watch::Step::READING_SAID)
    case judged.state
    when FirefightAi::Schemas::WatchReading::DONE then finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, judged.said)
    when FirefightAi::Schemas::WatchReading::FAILED then finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, judged.said)
    when FirefightAi::Schemas::WatchReading::RUNNING
      reading_started(watch, step)
      progress << "#{step.label}: #{moved.join(', ')}." if moved.any?
    end
  end

  # How long a reading has stayed the same, for a condition that names a time. nil when it just changed.
  def self.steady_words(step, now)
    steady = step.steady_since && now - step.steady_since
    "The reading has stayed the same for #{Integrations::Capabilities::History.duration(steady)}." if steady && steady >= Chat::Watch::CHECK_EVERY
  end

  # What done means for a reading, from the condition and the words it was given.
  def self.reading_goal(step)
    [ step.goal.presence || "#{step.label} finishes.", ("It is done when the reading says #{step.done_when}." if step.done_when.present?),
      ("It failed when the reading says #{step.failed_when}." if step.failed_when.present?) ].compact.join(" ")
  end

  def self.reading_started(watch, step)
    return unless step.started_told_at.nil? && step.started!(run_id: step.followed_run_id, at: Time.current)

    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} started.") if step.report_start
  end

  def self.finish_reading(watch, step, status, said)
    return unless step.finished!(status, reason: said)

    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, standing(watch, "#{step.label}: done.#{" #{said}" if said.present?}")) if status == Chat::Watch::Step::STATUS_SUCCEEDED
  end

  def self.says?(text, words) = words.present? && text.downcase.include?(words.downcase.strip)

  def self.excerpt(text, words)
    line = text.lines.find { |each| each.downcase.include?(words.downcase.strip) }
    "It reads: #{line.to_s.strip.truncate(300)}"
  end

  # Why a run failed, read only: the end of its build log for a build or a repository's CI, its app log for a deploy,
  # explained in a sentence or two when Halon is available, otherwise the lines that name an error.
  def self.why_failed(watch, step, run, reader, call, environment_row: nil)
    part = run.first_failed_part
    lines = (part && part_log(part, environment_row, reader)) || log_evidence(step, run, reader, call)
    evidence = [ run.detail, lines ].compact_blank.join("\n").truncate(EVIDENCE_LIMIT)
    explained = evidence.present? && judge(watch)&.why_failed(what: "#{step.label} (#{run.name || 'run'} #{run.number || run.id})", evidence: evidence)
    said = explained.presence || error_lines(lines) || run.detail.presence || "The provider did not say why."
    [ said, (run.url if run.url.present?) ].compact.join(" ")
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::OutOfCredit
    error_lines(lines) || run.detail.presence || "The provider did not say why."
  end

  def self.log_evidence(step, run, reader, call)
    build = Integrations::Capabilities::STREAM_BUILD
    streams = call.resource.kind == ResourceMap::KIND_REPOSITORY || step.label.match?(/\b(build|ci|tests?)\b/i) ? [ build ] : [ Integrations::Capabilities::STREAM_APP, build ]
    minutes = run.started_at ? (((Time.current - run.started_at) / 60).ceil + 5).clamp(5, Integrations::Capabilities::MAX_MINUTES) : 60
    streams.each do |stream|
      given = { Integrations::Capabilities::RESOURCE_ARG => call.resource.id, "stream" => stream, "minutes" => minutes, "limit" => LOG_LINES }
      answer = reader.read(Integrations::Capabilities::LOGS, given)
      text = Chat::SecretFree.redacted(answer.text) unless answer.failed?
      return text if text.present? && !text.start_with?("No log lines")
    rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered
      next
    end
    nil
  end

  def self.error_lines(text)
    found = text.to_s.lines.grep(/error|fail|exception|fatal/i).last(3).map(&:strip)
    found.any? ? "The log ends with: #{found.join(' / ').truncate(500)}" : nil
  end

  # A model only for a workspace where Halon may answer at all.
  def self.judge(watch)
    return if Investigation.unavailable_reason(watch.workspace)

    FirefightAi::WatchJudge.new(watch.workspace, inferable: watch.conversation.try(:subject), member: (watch.asker if watch.asker.is_a?(WorkspaceMembership)))
  end

  def self.conclude!(watch)
    steps = watch.steps.reload.to_a
    failed = steps.find { |step| step.status == Chat::Watch::Step::STATUS_FAILED }
    return finish!(watch, Chat::Watch::STATUS_FAILED, failed_words(watch, failed)) if failed
    return unless steps.all?(&:over?)

    followed = steps.select { |step| step.status == Chat::Watch::Step::STATUS_SUCCEEDED }
    return finish!(watch, Chat::Watch::STATUS_STOPPED, "I stopped #{Chat::Watch::Shown.named(watch)}, since none of it can be followed any more.") if followed.empty?

    took = Integrations::Capabilities::History.duration(Time.current - watch.created_at)
    lost = steps.size - followed.size
    finish!(watch, Chat::Watch::STATUS_SUCCEEDED,
            standing(watch, "#{Chat::Watch::Shown.name(watch)} is done. #{followed.size == 1 ? 'It' : 'Everything I followed'} finished within #{took}." \
                            "#{" #{lost} step#{'s' if lost > 1} could not be followed." if lost.positive?}"))
  end

  def self.failed_words(watch, step)
    took = step.seconds_taken && " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}"
    standing(watch, "#{step.label} failed#{took}, so I stopped #{Chat::Watch::Shown.named(watch)}. #{step.reason.presence || 'It did not say why.'}")
  end

  # What happened, then where that leaves what the person wanted and the next step Halon offers, when the watch was started
  # for a purpose. Said by a model from what happened only, and the purpose itself when Halon is not available.
  def self.standing(watch, happened)
    return happened if watch.purpose.blank?

    said = judge(watch)&.standing(purpose: watch.purpose, happened: happened)
    [ happened, said.presence || "This was for: #{watch.purpose}" ].join(" ")
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::OutOfCredit
    "#{happened} This was for: #{watch.purpose}"
  end

  def self.time_out!(watch)
    state = watch.open_steps.map { |step| "#{step.label}: #{step.last_state.presence || 'nothing seen yet'}" }.join(" ")
    took = Integrations::Capabilities::History.duration(watch.expires_at - watch.created_at)
    finish!(watch, Chat::Watch::STATUS_TIMED_OUT,
            standing(watch, "I stopped #{Chat::Watch::Shown.named(watch)} after #{took}, its time limit. Last I saw: #{state.truncate(600)}"))
  end

  def self.finish!(watch, status, outcome, stopped_by: nil)
    return false unless watch.finish!(status, outcome: outcome, stopped_by: stopped_by)

    tell!(watch, Chat::Watch::Update::KIND_ENDED, outcome)
    true
  end

  # Stops it for this person, saying so once. Returns why not, or nil.
  def self.stop!(watch, by:)
    blocked = watch.stop_blocked_reason(by)
    return blocked if blocked

    who = by.try(:display_name) || "Someone"
    member = by if by.is_a?(WorkspaceMembership)
    return Chat::Watch::NOTHING_TO_STOP unless finish!(watch, Chat::Watch::STATUS_STOPPED, "#{who} stopped #{Chat::Watch::Shown.named(watch)}.", stopped_by: member)

    nil
  end

  # Stop pressed on a line the watch said on the platform, by whoever pressed it. The watch's end is said where it
  # reports, as any stop is, and the pressed message loses its Stop once the watch is over, also when it had ended
  # already. Returns why it was not stopped, or nil.
  def self.stop_pressed!(update, by:, channel_id:, message_id:)
    watch = update.watch
    blocked = stop!(watch, by: by)
    take_stop_away(watch, update, channel_id, message_id) unless watch.reload.active?
    blocked
  end

  def self.take_stop_away(watch, update, channel_id, message_id)
    return if channel_id.blank? || message_id.blank?

    conversation = watch.conversation
    adapter = WorkspaceAdapter.for(watch.workspace)
    adapter.update_watch_update(channel_id: channel_id, message_id: message_id, update: said(watch, update),
                                direct: adapter.direct_conversation?(channel_id: channel_id),
                                conversation_id: (conversation.id if conversation.personal?))
  rescue AdapterError => error
    Rails.logger.warn({ event: "watch.stop_unshown", watch_id: watch.id, update_id: update.id, error: error.class.name }.to_json)
  end

  # A live update about a connection a watch reads through wakes it now rather than at the next sweep.
  def self.wake!(environment_row)
    Chat::Watch.reading_through(environment_row).pluck(:id).each { |id| WatchCheckJob.perform_later(id) }
  end

  # Fresh beats remembered. A reading Halon took in its chat with the same read one of the chat's watches makes is taken
  # by the watch now. A reading step judges Halon's reading as its own, and a run step reads that run again at once.
  # When the step moves, the watch says so on the chat's page and Halon is handed a note to tell the person that what
  # the watch had and the reading disagreed. Answers that note, or nil.
  def self.observe!(chat, tool_name, arguments, text, now: Time.current)
    notes = chat.watches.active.includes(:steps).flat_map { |watch| observed(watch, tool_name.to_s, arguments, text, now) }
    notes.join("\n").presence
  end

  def self.observed(watch, tool_name, arguments, text, now)
    steps = watch.open_steps.reject(&:repairing?).select { |step| reads_the_same?(step, tool_name, arguments) }
    return [] if steps.empty? || !watch.claim_check!(now)

    meter = Chat::Watch::Meter.new(watch.reads_left(now))
    read_all = true
    begin
      had = steps.to_h { |step| [ step.id, [ step.status, Chat::Watch::Shown.step_state(step) ] ] }
      progress = []
      read_all = read_steps(watch, steps, meter, now, progress, reading: text)
      tell!(watch, Chat::Watch::Update::KIND_PROGRESS, progress.join("\n")) if progress.any?
      notes = steps.filter_map { |step| corrected(watch, step.reload, *had.fetch(step.id)) }
      conclude!(watch)
      notes
    ensure
      settle_reads!(watch, meter, now, read_all: read_all)
    end
  end

  # Whether a call is the read a step makes, meaning the same read tool with the same arguments, or the same capability
  # on the same resource.
  def self.reads_the_same?(step, tool_name, arguments)
    given = comparable(arguments)
    return step.tool_name == tool_name && comparable(step.arguments) == given if step.read_tool?

    resource = given[Integrations::Capabilities::RESOURCE_ARG]
    step.spec&.tool_name == tool_name && resource.present? && resource.casecmp?(step.arguments[Integrations::Capabilities::RESOURCE_ARG].to_s)
  end

  def self.comparable(arguments)
    arguments.to_h.deep_stringify_keys.except(Chat::Tools::INTENT_ARG).transform_values { |value| value.is_a?(Enumerable) ? value.to_json : value.to_s }
  end

  # The step moved on Halon's reading, said on the chat's page where the person sees what the watch had change, and the
  # note Halon reads. Halon says it in its own answer, so it is not posted anywhere else.
  def self.corrected(watch, step, status_before, state_before)
    return if step.status == status_before

    now_words = Chat::Watch::Shown.step_state(step)
    phrases = Chat::Watch::Shown::STEP_PHRASES
    update = watch.updates.create!(kind: Chat::Watch::Update::KIND_CORRECTED, told_at: Time.current, text: Chat::SecretFree.redacted(
      "A fresh reading in the chat shows #{step.label} #{phrases.fetch(step.status)}, where #{Chat::Watch::Shown.named(watch)} still had it " \
      "#{phrases.fetch(status_before)}. It now goes by the fresh reading."
    ))
    Conversation::LiveDelivery.watch_moved(watch.conversation)
    "#{Chat::Watch::Shown.name(watch)} had #{step.label} as: #{state_before} The reading you just took shows: #{now_words} " \
      "The fresh reading wins, and the watch now goes by it (#{update.text}) Tell the person in a sentence that the watch had it " \
      "differently and which is true now, and never repeat what the watch had as current."
  end

  # Says one line everywhere the watch reports: kept with the chat and drawn on its page, in the chat's thread when
  # it has one, and in the asker's direct messages, unless the thread already is one with them.
  def self.tell!(watch, kind, text)
    update = watch.updates.create!(kind: kind, text: Chat::SecretFree.redacted(text))
    conversation = watch.conversation
    Conversation::LiveDelivery.watch_moved(conversation)
    said = said(watch, update)
    adapter = WorkspaceAdapter.for(watch.workspace)
    in_thread = conversation.thread_id.present?
    post(watch, update) { adapter.post_watch_update(channel_id: conversation.channel_id, thread_id: conversation.thread_id, update: said) } if in_thread
    user_id = watch.asker.try(:platform_user_id)
    return update if user_id.blank? || (in_thread && adapter.direct_conversation?(channel_id: conversation.channel_id))

    post(watch, update) { adapter.post_watch_update_to_user(user_id: user_id, update: said, conversation_id: (conversation.id if conversation.personal?)) }
    update
  end

  def self.post(watch, update)
    yield
  rescue AdapterError => error
    Rails.logger.warn({ event: "watch.untold", watch_id: watch.id, update_id: update.id, error: error.class.name }.to_json)
  end

  def self.said(watch, update)
    tone = update.kind == Chat::Watch::Update::KIND_ENDED ? ENDED_TONES.fetch(watch.status, TONE_DONE) : update.kind
    Said.new(id: update.id, watch_id: watch.id, title: watch.title, name: Chat::Watch::Shown.name(watch), kind: update.kind, tone: tone,
             text: update.text, at: update.created_at, live: watch.active?, link: Chat::Watch::Shown.link(watch))
  end

  # What Halon hears at its next turn: each line its watches said since, and the ones still going, once each.
  def self.untold_note(chat)
    updates = Chat::Watch::Update.joins(:watch).where(chat_watches: { chat_id: chat.id }).untold.includes(:watch).order(:created_at).to_a
    return nil if updates.empty?

    Chat::Watch::Update.where(id: updates.map(&:id)).update_all(told_at: Time.current)
    Chat::Watch.where(chat_id: chat.id, id: updates.map(&:watch_id)).untold.update_all(told_at: Time.current)
    lines = updates.map { |update| "- #{Chat::Watch::Shown.name(update.watch)}#{" (for: #{update.watch.purpose})" if update.watch.purpose.present?}: #{update.text}" }
    "What your watches said since you last looked, already told to the person. A reading you take now beats any of it:\n#{lines.join("\n")}"
  end
end
