# Watches from start to end. Halon starts one when a person asks to be told later, the sweep and live updates check it,
# and each milestone and the end are said once: in the chat, in its thread when it has one, and in the asker's
# direct messages. A watch only reads, as the person who asked, through the capabilities.
module Conversation::Watches
  HISTORY = Integrations::Capabilities::HISTORY
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
    planned, cannot = plan(given, reader)
    return "Nothing was started, since none of it can be followed. #{cannot.join(' ')}" if planned.empty?

    usual = planned.filter_map { |step| step[:usual] }.sum.nonzero?
    limit = Chat::Watch.limit_for(asked_minutes: arguments["minutes"], usual_seconds: usual, remembered_minutes: arguments["expected_minutes"])
    title = arguments["title"].to_s.strip.presence || planned.first[:label]
    watch = create!(turn, title, limit, planned)
    Conversation::LiveDelivery.watch_moved(turn.conversation)

    [ "Started watching #{title}. Tell the person, in your own words: #{limit_sentence(limit)}",
      cannot.any? ? "Also tell them what it cannot follow: #{cannot.join(' ')}" : nil,
      "Each milestone and the end come to this chat and to their direct messages on their own, so never check it " \
      "again yourself unless they ask. It can be stopped from the chat or with stop_watch (watch #{watch.id})." ].compact.join("\n")
  end

  # Each step routed as the asker before anything is kept, history read once for how long it usually takes.
  def self.plan(given, reader)
    planned = []
    cannot = []
    given.each_with_index do |step, index|
      label = step["label"].to_s.strip.presence || "Step #{index + 1}"
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

  def self.first_read(reader, key, arguments, step)
    return [ nil, reader.route(key, arguments).environment_row ] unless key == HISTORY

    answer = reader.read(key, arguments)
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if runs.nil?

    [ Integrations::Capabilities::History.usual_seconds(runs, name: step["name"]), answer.call.environment_row ]
  end

  def self.create!(turn, title, limit, planned)
    Chat::Watch.transaction do
      watch = Chat::Watch.create!(
        chat: turn.conversation.chat_record, workspace: turn.workspace, asker: turn.asker, title: title.truncate(120),
        expires_at: limit.seconds.seconds.from_now, usual_seconds: limit.usual_seconds, limit_basis: limit.basis
      )
      planned.each_with_index do |planned_step, position|
        given = planned_step[:step]
        watch.steps.create!(
          position: position, label: planned_step[:label].truncate(120), capability: planned_step[:key], arguments: planned_step[:arguments],
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

  # One check: each open step read once, its milestones said once, and the watch ended when they are all over or its
  # time ran out. A watch another worker holds is left to it.
  def self.check!(watch, now: Time.current)
    return unless watch.active? && watch.claim_check!(now)

    begin
      return time_out!(watch) if now >= watch.expires_at

      reader = Conversation::Watches::Reader.new(workspace: watch.workspace, principal: watch.asker, conversation: watch.conversation)
      watch.open_steps.each { |step| check_step(watch, step, reader, now) }
      conclude!(watch)
    ensure
      watch.release_check!
    end
  end

  def self.check_step(watch, step, reader, now)
    step.history? ? follow_run(watch, step, reader, now) : follow_reading(watch, step, reader)
  rescue Conversation::Watches::Reader::Unanswered => unanswered
    step.seen!(digest: step.last_digest, state: "Could not read it just now: #{unanswered.message}")
  rescue Conversation::Watches::Reader::Refused => refused
    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "I can no longer follow #{step.label}. #{refused.message}") if step.unfollowable!(refused.message)
  end

  def self.follow_run(watch, step, reader, now)
    answer = reader.read(HISTORY, step.arguments)
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if runs.nil?

    run = step.run_among(runs)
    return step.seen!(digest: nil, state: "No run of #{step.label} has started yet.") unless run

    step.seen!(digest: run.status, state: Integrations::Capabilities::History.line(run))
    unless run.finished?
      said_start = step.started_told_at.nil? && step.started!(run_id: run.id.to_s, at: run.started_at, url: run.url)
      tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} started.") if said_start && step.report_start
      tell!(watch, Chat::Watch::Update::KIND_SLOW, slow_words(step, now)) if step.slow?(now) && step.slow_told!
      return
    end

    ended = RUN_ENDS.fetch(run.status)
    reason = why_failed(watch, step, run, reader, answer.call) if ended == Chat::Watch::Step::STATUS_FAILED
    return unless step.finished!(ended, reason: reason, at: run.finished_at, run_id: run.id.to_s, url: run.url, started: run.started_at)

    took = step.seconds_taken && " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}"
    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} succeeded#{took}.") if ended == Chat::Watch::Step::STATUS_SUCCEEDED
  end

  def self.slow_words(step, now)
    so_far = Integrations::Capabilities::History.duration(now - step.started_at)
    "#{step.label} is taking longer than usual, #{so_far} so far where it usually takes #{Integrations::Capabilities::History.duration(step.usual_seconds)}."
  end

  # A reading that is not a run: done or failed by the words the watch was given, and only when it changed and no words
  # decide it, judged by a model against its goal.
  def self.follow_reading(watch, step, reader)
    answer = reader.read(step.capability, step.arguments)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if answer.failed?

    text = Chat::SecretFree.redacted(answer.text)
    digest = Digest::SHA256.hexdigest(text.gsub(CLOCK, ""))
    before = step.last_state
    changed = digest != step.last_digest
    step.seen!(digest: digest, state: text)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, excerpt(text, step.failed_when)) if says?(text, step.failed_when)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, nil) if says?(text, step.done_when)
    return unless changed && step.goal.present?

    judged = judge(watch)&.reading(goal: step.goal, before: before, now: text.truncate(EVIDENCE_LIMIT))
    case judged&.state
    when FirefightAi::Schemas::WatchReading::DONE then finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, judged.said)
    when FirefightAi::Schemas::WatchReading::FAILED then finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, judged.said)
    end
  end

  def self.finish_reading(watch, step, status, said)
    return unless step.finished!(status, reason: said)

    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label}: done.#{" #{said}" if said.present?}") if status == Chat::Watch::Step::STATUS_SUCCEEDED
  end

  def self.says?(text, words) = words.present? && text.downcase.include?(words.downcase.strip)

  def self.excerpt(text, words)
    line = text.lines.find { |each| each.downcase.include?(words.downcase.strip) }
    "It reads: #{line.to_s.strip.truncate(300)}"
  end

  # Why a run failed, read only: the end of its build log for a build or a repository's CI, its app log for a deploy,
  # explained in a sentence or two when Halon is available, otherwise the lines that name an error.
  def self.why_failed(watch, step, run, reader, call)
    lines = log_evidence(step, run, reader, call)
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
    return finish!(watch, Chat::Watch::STATUS_STOPPED, "I stopped watching #{watch.title}, since I can no longer read any of it.") if followed.empty?

    took = Integrations::Capabilities::History.duration(Time.current - watch.created_at)
    lost = steps.size - followed.size
    finish!(watch, Chat::Watch::STATUS_SUCCEEDED,
            "Done: #{watch.title}. #{followed.size == 1 ? 'It' : 'Everything I followed'} finished within #{took}.#{" #{lost} step#{'s' if lost > 1} could not be followed." if lost.positive?}")
  end

  def self.failed_words(watch, step)
    took = step.seconds_taken && " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}"
    "#{step.label} failed#{took}, so I stopped watching #{watch.title}. #{step.reason.presence || 'It did not say why.'}"
  end

  def self.time_out!(watch)
    state = watch.open_steps.map { |step| "#{step.label}: #{step.last_state.presence || 'nothing seen yet'}" }.join(" ")
    finish!(watch, Chat::Watch::STATUS_TIMED_OUT,
            "I stopped watching #{watch.title} after #{Integrations::Capabilities::History.duration(watch.expires_at - watch.created_at)}, the time limit. Last I saw: #{state.truncate(600)}")
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
    lines = updates.map { |update| "- #{update.watch.title}: #{update.text}" }
    "What your watches said since you last looked, already told to the person:\n#{lines.join("\n")}"
  end
end
