# Watches from start to end. Halon starts one when a person asks to be told later, the sweep and live updates check it,
# and each milestone and the end are said once: in the chat, in its thread when it has one, and in the asker's
# direct messages. A watch only reads, as the person who asked, through the capabilities.
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

  # One line a watch said, as the chat, the platform's message and MCP show it.
  Said = Data.define(:id, :watch_id, :title, :kind, :tone, :text, :at)

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

    reader = Conversation::Watches::Reader.new(workspace: workspace, principal: asker, conversation: turn.conversation)
    agent = Conversation::Watches::Agent.new(workspace: workspace, asker: asker, conversation: turn.conversation)
    planned, cannot = plan(given, reader, agent)
    return "Nothing was started, since none of it can be followed. #{cannot.join(' ')}" if planned.empty?

    usual = planned.filter_map { |step| step[:usual] }.sum.nonzero?
    limit = Chat::Watch.limit_for(asked_minutes: arguments["minutes"], usual_seconds: usual, remembered_minutes: arguments["expected_minutes"])
    title = arguments["title"].to_s.strip.presence || planned.first[:label]
    watch = create!(turn, title, limit, planned, purpose: arguments["purpose"].to_s.strip.presence)
    Conversation::LiveDelivery.watch_moved(turn.conversation)
    # Something that fails the moment it starts is told within seconds rather than at the next sweep.
    WatchCheckJob.perform_later(watch.id)

    [ "Started watching #{title}. Tell the person, in your own words: #{limit_sentence(limit)}",
      cannot.any? ? "Also tell them what it cannot follow: #{cannot.join(' ')}" : nil,
      "Each milestone and the end come to this chat and to their direct messages on their own, so never check it " \
      "again yourself unless they ask. It can be stopped from the chat or with stop_watch (watch #{watch.id})." ].compact.join("\n")
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
      if key != HISTORY && [ step["done_when"], step["failed_when"], step["goal"] ].all?(&:blank?)
        next cannot << "#{label} needs what counts as done for it (done_when, failed_when or goal)."
      end

      usual, row = first_read(reader, key, arguments, step)
      planned << { label: label, key: key, arguments: arguments, step: step, usual: usual, row: row }
    rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered => refused
      cannot << "#{label} cannot be followed. #{refused.message}"
    end
    [ planned, cannot ]
  end

  def self.plan_tool_step(step, label, reader, agent, planned, cannot)
    if [ step["done_when"], step["failed_when"], step["goal"] ].all?(&:blank?)
      return cannot << "#{label} needs what counts as done for it (done_when, failed_when or goal)."
    end

    arguments = step["arguments"].is_a?(Hash) ? step["arguments"].transform_keys(&:to_s).except(Chat::Tools::INTENT_ARG) : {}
    said = reader.read_tool(agent, step["tool"], arguments)
    return cannot << "#{label} cannot be followed, since reading it failed: #{Chat::SecretFree.redacted(said.text).truncate(300)}" if said.failed?

    planned << { label: label, key: Chat::Watch::Step::READ_TOOL, tool: step["tool"].to_s, arguments: arguments, step: step, usual: nil, row: nil }
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered => refused
    cannot << "#{label} cannot be followed. #{refused.message}"
  end

  def self.first_read(reader, key, arguments, step)
    return [ nil, reader.route(key, arguments).environment_row ] unless key == HISTORY

    answer = reader.read(key, arguments)
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if runs.nil?

    [ Integrations::Capabilities::History.usual_seconds(runs, name: step["name"]), answer.call.environment_row ]
  end

  def self.create!(turn, title, limit, planned, purpose: nil)
    Chat::Watch.transaction do
      watch = Chat::Watch.create!(
        chat: turn.conversation.chat_record, workspace: turn.workspace, asker: turn.asker, title: title.truncate(120),
        purpose: purpose&.truncate(Chat::Watch::PURPOSE_LIMIT),
        expires_at: limit.seconds.seconds.from_now, usual_seconds: limit.usual_seconds, limit_basis: limit.basis
      )
      planned.each_with_index do |planned_step, position|
        given = planned_step[:step]
        watch.steps.create!(
          position: position, label: planned_step[:label].truncate(120), capability: planned_step[:key], arguments: planned_step[:arguments],
          tool_name: planned_step[:tool],
          integration_environment: planned_step[:row], run_name: given["name"].presence, run_ref: given["run"].presence,
          report_start: ActiveModel::Type::Boolean.new.cast(given["report_start"]) || false, done_when: given["done_when"].presence,
          failed_when: given["failed_when"].presence, goal: given["goal"].presence, usual_seconds: planned_step[:usual]
        )
      end
      watch
    end
  end

  def self.key_for(name)
    spec = Integrations::Capabilities::SPECS.values.find { |each| each.tool_name == name.to_s || each.key == name.to_s }
    spec.key if spec && !spec.writes
  end

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
  def self.check!(watch, now: Time.current)
    return unless watch.active? && watch.claim_check!(now)

    begin
      return time_out!(watch) if now >= watch.expires_at

      reader = Conversation::Watches::Reader.new(workspace: watch.workspace, principal: watch.asker, conversation: watch.conversation)
      agent = Conversation::Watches::Agent.new(workspace: watch.workspace, asker: watch.asker, conversation: watch.conversation)
      progress = []
      watch.open_steps.each { |step| check_step(watch, step, reader, agent, now, progress) }
      tell!(watch, Chat::Watch::Update::KIND_PROGRESS, progress.join("\n")) if progress.any?
      conclude!(watch)
    ensure
      watch.release_check!
    end
  end

  def self.check_step(watch, step, reader, agent, now, progress)
    step.history? ? follow_run(watch, step, reader, now, progress) : follow_reading(watch, step, reader, agent, progress)
  rescue Conversation::Watches::Reader::Unanswered => unanswered
    step.seen!(digest: step.last_digest, state: "Could not read it just now: #{unanswered.message}")
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

  # No run showed up where one was expected, so the person is told and Halon is asked to find another way to follow it,
  # in the chat it was started from, reading only.
  def self.hand_back!(watch, step, runs, now)
    return unless step.handed_back!

    waited = Integrations::Capabilities::History.duration(now - [ watch.created_at, *watch.steps.filter_map(&:finished_at) ].max)
    latest = runs.first(3).map { |run| Integrations::Capabilities::History.line(run) }.join("\n")
    step.unfollowable!(HANDED_BACK)
    tell!(watch, Chat::Watch::Update::KIND_HANDED_BACK,
          "I could not find a run of #{step.label} in its history after #{waited}, so I am finding another way to follow it.")
    ConversationReplyJob.perform_later(watch.conversation.id, (watch.asker.id if watch.asker.is_a?(WorkspaceMembership)), nil, step.id)
    Rails.logger.info({ event: "watch.handed_back", watch_id: watch.id, step_id: step.id, latest: latest.truncate(300) }.to_json)
  end

  HANDED_BACK = "No run of it showed up in its history, so Halon is finding another way to follow it.".freeze
  RUN_ARG = "run".freeze

  # What Halon reads when a step is handed back: what it could not find, what the history did show, why the person wanted
  # it, and to re-plan by reading, never by changing anything.
  def self.hand_back_note(step)
    watch = step.watch
    [
      "Your watch #{watch.title} could not follow #{step.label}: no run of it showed up in its history (#{step.arguments.except(Chat::Tools::INTENT_ARG).to_json}).",
      ("It was started for: #{watch.purpose}" if watch.purpose.present?),
      "Find the run another way with the provider's read tools, its skill or search_docs, such as a GET request for that run, then start a new " \
      "watch whose step names that read tool with its arguments, carrying the same purpose. Change nothing in this turn. Tell the person " \
      "in a sentence or two what you are now following, or what you could not find."
    ].compact.join(" ")
  end

  def self.slow_words(step, now)
    so_far = Integrations::Capabilities::History.duration(now - step.started_at)
    "#{step.label} is taking longer than usual, #{so_far} so far where it usually takes #{Integrations::Capabilities::History.duration(step.usual_seconds)}."
  end

  # A reading that is not a run: done or failed by the words the watch was given, and only when it changed and no words
  # decide it, judged by a model into not started, running, done or failed, with the jobs or steps it lists. A reading
  # that shows it begun moves the step to running.
  def self.follow_reading(watch, step, reader, agent, progress)
    answer = step.read_tool? ? reader.read_tool(agent, step.tool_name, step.arguments) : reader.read(step.capability, step.arguments)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if answer.failed?

    text = Chat::SecretFree.redacted(answer.text)
    digest = Digest::SHA256.hexdigest(text.gsub(CLOCK, ""))
    before = step.last_state
    changed = digest != step.last_digest
    step.seen!(digest: digest, state: text)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, excerpt(text, step.failed_when)) if says?(text, step.failed_when)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, nil) if says?(text, step.done_when)
    return unless changed

    judged = judge(watch)&.reading(goal: reading_goal(step), before: before, now: text.truncate(EVIDENCE_LIMIT), so_far: step.running? ? "running" : "not started")
    return unless judged

    moved = step.progress!(judged.parts.filter_map { |name, state| [ name, READING_PARTS[state] ] if READING_PARTS[state] }, said: Chat::Watch::Step::READING_SAID)
    case judged.state
    when FirefightAi::Schemas::WatchReading::DONE then finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, judged.said)
    when FirefightAi::Schemas::WatchReading::FAILED then finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, judged.said)
    when FirefightAi::Schemas::WatchReading::RUNNING
      reading_started(watch, step)
      progress << "#{step.label}: #{moved.join(', ')}." if moved.any?
    end
  end

  # What done means for a reading, from the goal and the words it was given.
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
    streams = call.resource.kind == ResourceMap::KIND_REPOSITORY || step.label.match?(/build|ci|test/i) ? %w[build] : %w[app build]
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
    if followed.empty?
      handed = steps.any? { |step| step.handed_back_at.present? }
      return finish!(watch, Chat::Watch::STATUS_STOPPED, handed ? "I stopped this watch on #{watch.title}, since Halon is finding another way to follow it." : "I stopped watching #{watch.title}, since I can no longer read any of it.")
    end

    took = Integrations::Capabilities::History.duration(Time.current - watch.created_at)
    lost = steps.size - followed.size
    finish!(watch, Chat::Watch::STATUS_SUCCEEDED,
            standing(watch, "Done: #{watch.title}. #{followed.size == 1 ? 'It' : 'Everything I followed'} finished within #{took}.#{" #{lost} step#{'s' if lost > 1} could not be followed." if lost.positive?}"))
  end

  def self.failed_words(watch, step)
    took = step.seconds_taken && " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}"
    standing(watch, "#{step.label} failed#{took}, so I stopped watching #{watch.title}. #{step.reason.presence || 'It did not say why.'}")
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
    finish!(watch, Chat::Watch::STATUS_TIMED_OUT,
            standing(watch, "I stopped watching #{watch.title} after #{Integrations::Capabilities::History.duration(watch.expires_at - watch.created_at)}, the time limit. Last I saw: #{state.truncate(600)}"))
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
    return Chat::Watch::NOTHING_TO_STOP unless finish!(watch, Chat::Watch::STATUS_STOPPED, "#{who} stopped the watch on #{watch.title}.", stopped_by: member)

    nil
  end

  # A live update about a connection a watch reads through wakes it now rather than at the next sweep.
  def self.wake!(environment_row)
    Chat::Watch.reading_through(environment_row).pluck(:id).each { |id| WatchCheckJob.perform_later(id) }
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
    Said.new(id: update.id, watch_id: watch.id, title: watch.title, kind: update.kind, tone: tone, text: update.text, at: update.created_at)
  end

  # What Halon hears at its next turn: each line its watches said since, and the ones still going, once each.
  def self.untold_note(chat)
    updates = Chat::Watch::Update.joins(:watch).where(chat_watches: { chat_id: chat.id }).untold.includes(:watch).order(:created_at).to_a
    return nil if updates.empty?

    Chat::Watch::Update.where(id: updates.map(&:id)).update_all(told_at: Time.current)
    Chat::Watch.where(chat_id: chat.id, id: updates.map(&:watch_id)).untold.update_all(told_at: Time.current)
    lines = updates.map { |update| "- #{update.watch.title}#{" (for: #{update.watch.purpose})" if update.watch.purpose.present?}: #{update.text}" }
    "What your watches said since you last looked, already told to the person:\n#{lines.join("\n")}"
  end
end
