# Watches from start to end. Halon writes one when a person asks to be told later, as keep reading this until that holds,
# with any read it may make. The sweep and live updates check it within a ceiling on reads. Each milestone and the end
# are said once in the chat, and move one card in its thread when it has one and one in the asker's direct messages,
# with the end also said in a line of its own there. A read that finds
# nothing to follow is handed back to Halon to repair, and a reading Halon takes in the chat overrides what the watch
# had. A watch only reads, as the person who asked.
module Conversation::Watches
  HISTORY = Integrations::Capabilities::HISTORY
  # How a job or step inside a run stands, in the words its progress is said in.
  PART_STATES = {
    Integrations::Capabilities::History::QUEUED => Chat::Watch::Step::PART_WAITING,
    Integrations::Capabilities::History::WAITING => Chat::Watch::Step::PART_HELD,
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

  # A watch's card on the platform as it stands now, one per place it reports, edited in place. what is what it is for,
  # state how it stands in a word, why one short plain line on that. update_id is a line it said, which Stop names.
  # link is the page of what it follows when the provider gave one, conversation_id the dashboard chat a card in direct
  # messages offers to open.
  Card = Data.define(:watch_id, :update_id, :status, :state, :what, :why, :link, :conversation_id) do
    def live? = status == Chat::Watch::STATUS_ACTIVE
  end
  # Where a card goes: the place, the channel or person, and the thread for a card in a chat's thread.
  Place = Data.define(:key, :channel_id, :thread_id) do
    def direct? = key == Chat::Watch::PLACE_DIRECT
  end

  ADD_TO_ARG = "add_to".freeze
  SEPARATE_ARG = "separate".freeze
  # Where the person sees the watches going in a dashboard chat, which Halon points to rather than listing them.
  STRIP_NOTE = "The watches going show in the Watching strip above the message box, each opening to its card, so point " \
               "there rather than listing them.".freeze

  # Only the dashboard draws the strip, so a chat in Slack is never pointed to it.
  def self.strip_note(turn) = (STRIP_NOTE if turn.conversation.personal?)

  # Starts a watch for whoever asks this turn, and answers what Halon tells the person: how long it will watch and
  # why, and anything it cannot follow. arguments are start_watch's, with string keys. One watch per subject, so
  # steps given add_to join that watch. With choose, as Halon's start_watch asks, a watch of theirs already going in
  # the chat means Halon says first whether these join it or are separate. A runbook's own watch starts as it always has.
  def self.start(turn, arguments, choose: false)
    workspace = turn.workspace
    asker = turn.asker
    return "Nobody can be credited with this watch, so it was not started." unless asker
    return add_to(turn, arguments) if arguments[ADD_TO_ARG].present?

    going = Array(turn.chat&.watches&.going_for(asker))
    return which_watch(going) if choose && going.any? && !ActiveModel::Type::Boolean.new.cast(arguments[SEPARATE_ARG])

    full = Chat::Watch.full_reason(workspace)
    return full if full

    given = steps_given(arguments)
    return NO_STEPS if given.empty?
    return "A watch follows at most #{Chat::Watch::MAX_STEPS} steps. Watch the ones that matter most." if given.size > Chat::Watch::MAX_STEPS

    orders, wrong = order_of(given)
    return "Nothing was started. #{wrong}" if wrong

    ceiling = Chat::Watch.ceiling_for(arguments["reads_per_hour"], given.size)
    meter = Chat::Watch::Meter.new(ceiling)
    reader, agent = readers(workspace, asker, turn.conversation, meter)
    planned, cannot = plan(given, reader, agent)
    planned = placed(planned, cannot, orders, given)
    return "Nothing was started, since none of it can be followed. #{cannot.join(' ')}" if planned.empty?

    usual = planned.filter_map { |step| step[:usual] }.sum.nonzero?
    limit = Chat::Watch.limit_for(asked_minutes: arguments["minutes"], usual_seconds: usual, remembered_minutes: arguments["expected_minutes"])
    title = arguments["title"].to_s.strip.presence || planned.first[:label]
    watch = create!(turn, title, limit, planned, purpose: arguments["purpose"].to_s.strip.presence, reads_per_hour: ceiling,
                    reads_per_hour_asked: arguments["reads_per_hour"].to_i.positive?)
    watch.count_reads!(meter.count)
    deploys = deploy_words(watch.steps)
    Conversation::LiveDelivery.watch_moved(turn.conversation) if turn.conversation.is_a?(Conversation)
    # Something that fails the moment it starts is told within seconds rather than at the next sweep.
    WatchCheckJob.perform_later(watch.id)

    [ "Started #{Chat::Watch::Shown.name(watch)}. Tell the person, in your own words: #{limit_sentence(limit)} " \
      "It reads at most #{ceiling} times an hour, which the card shows.",
      cannot.any? ? "Also tell them what it cannot follow: #{cannot.join(' ')}" : nil,
      deploys,
      "Each milestone and the end come to this chat and to their direct messages on their own, so never check it " \
      "again yourself unless they ask. When a step's read finds nothing to follow, it is handed back to you to repair " \
      "with repair_watch. It can be stopped from the chat or with stop_watch (watch #{watch.id}).", strip_note(turn) ].compact.join("\n")
  end

  # Nothing starts while the chat has a watch of this asker's going, until Halon says whether these steps follow the same
  # subject, which a model reads far better from the person's words than any match on names or resources could.
  def self.which_watch(going)
    listed = going.map do |watch|
      steps = watch.steps.map(&:label).join(", ")
      "- #{Chat::Watch::Shown.name(watch)} (watch #{watch.id})#{" for: #{watch.purpose}" if watch.purpose.present?}. Steps: #{steps}."
    end
    "Nothing was started yet, since this chat already has #{going.size == 1 ? 'a watch' : 'watches'} going:\n#{listed.join("\n")}\n" \
      "Keep one watch per subject. When these steps follow the same release, deploy, run or incident as one of them, such as " \
      "the rollout and the health checks after a release build, call start_watch again with #{ADD_TO_ARG} and its id, and " \
      "they join it. When they follow something unrelated, such as a database backup during a release, call it again with " \
      "#{SEPARATE_ARG} true."
  end

  # Steps on the same subject join the watch already following it, after its own, rather than start another. Its limit
  # moves to leave them time to finish, its ceiling rises with them unless Halon set it, and the watch says what joined
  # wherever it reports. Answers what Halon tells the person.
  def self.add_to(turn, arguments)
    watch_id = arguments[ADD_TO_ARG].to_s
    watch = turn.chat&.watches&.find_by(id: watch_id)
    return "No watch #{watch_id} in this chat. list_watches names them." unless watch

    given = steps_given(arguments)
    return NO_STEPS if given.empty?

    blocked = watch.add_blocked_reason(turn.asker, given.size)
    return blocked if blocked

    orders, wrong = order_of(given, watch.steps.to_a)
    return "Nothing was added. #{wrong}" if wrong

    now = Time.current
    ceiling = watch.ceiling_after_adding(arguments["reads_per_hour"], given.size)
    meter = Chat::Watch::Meter.new(watch.reads_left(now, ceiling: ceiling))
    reader, agent = readers(turn.workspace, turn.asker, turn.conversation, meter)
    planned, cannot = plan(given, reader, agent)
    planned = placed(planned, cannot, orders, given, before: watch.steps.to_a)
    return "Nothing was added, since none of it can be followed. #{cannot.join(' ')}" if planned.empty?

    usual = planned.filter_map { |step| step[:usual] }.sum.nonzero?
    limit = Chat::Watch.limit_for(asked_minutes: arguments["minutes"], usual_seconds: usual, remembered_minutes: arguments["expected_minutes"])
    needed = [ now + limit.seconds, watch.created_at + Chat::Watch::LONGEST ].min
    # A limit the person asked for stays theirs. Only one Halon chose moves later for the steps that joined.
    kept = watch.limit_basis == Chat::Watch::BASIS_ASKED && !arguments["minutes"].to_i.positive?
    until_at = kept ? watch.expires_at : needed
    limit_before = watch.expires_at
    steps = planned.map { |planned_step| { label: planned_step[:label].truncate(120), **read_of(planned_step) } }
    last_before = watch.steps.maximum(:position).to_i
    added = watch.add_steps!(steps, until_at: until_at, reads_per_hour: ceiling, title: arguments["title"].to_s.strip.presence,
                                    purpose: arguments["purpose"].to_s.strip.presence, now: now)
    return "#{Chat::Watch::Shown.name(watch)} ended just now, so nothing was added. Start a new watch for these steps." unless added

    watch.count_reads!(meter.count)
    deploys = deploy_words(watch.steps.where("position > ?", last_before))
    labels = planned.map { |planned_step| planned_step[:label] }.to_sentence
    moved = watch.expires_at > limit_before
    # Halon says it in its own answer, so it is not heard again at the next turn.
    tell!(watch, Chat::Watch::Update::KIND_STEPS_ADDED, steps_added_words(watch, labels, moved)).update_columns(told_at: Time.current)
    WatchCheckJob.perform_later(watch.id)

    [ "Added #{labels} to #{Chat::Watch::Shown.name(watch)} (watch #{watch.id}) rather than starting another watch. Tell the person, " \
      "in your own words, that the watch they have now follows these too. #{added_limit_words(watch, limit, moved, short: kept && needed > watch.expires_at)} " \
      "It reads at most #{watch.reads_per_hour} times an hour, which the card shows.",
      cannot.any? ? "Also tell them what it cannot follow: #{cannot.join(' ')}" : nil,
      deploys,
      "Each milestone and the end come to this chat and to their direct messages on their own, so never check it again yourself unless they ask.",
      strip_note(turn) ].compact.join("\n")
  end

  # Each step that begins waiting for a deploy says on its row which deploy, and Halon tells the person.
  def self.deploy_words(steps)
    waiting = steps.select(&:waits_for_deploy?).each { |step| step.summarized!(step.deploy_start_words) }
    return if waiting.empty?

    "Each step that waits for a deploy counts only one newer than the deploy live when it began. Tell them what it waits for: " \
      "#{waiting.map { |step| "#{step.label}: #{step.summary}" }.join(' ')}"
  end

  NO_STEPS = "Say what to watch, as one or more steps, each naming a capability that reads and a resource.".freeze

  def self.steps_given(arguments) = Array(arguments["steps"]).map { |step| step.to_h.transform_keys(&:to_s) }

  # What a given step is called before it is planned, as plan names it.
  def self.given_label(step, index) = step["label"].to_s.strip.presence || "Step #{index + 1}"

  # The steps each given step waits for, as indexes among the watch's own steps (before) and then the given ones, from
  # the labels or numbers counting from 1 that Halon gave. Answers [orders, nil], or [nil, why not] as a sentence.
  def self.order_of(given, before = [])
    labels = before.map(&:label) + given.each_with_index.map { |step, index| given_label(step, index) }
    orders = given.each_with_index.map do |step, index|
      refs = Array(step[Chat::Watch::SPEC_KEYS[:waits_for]]).map(&:to_s).compact_blank
      at = before.size + index
      indexes, wrong = Chat::Watch::Step.prerequisites_named(labels[at], refs, labels, at)
      return [ nil, wrong ] if wrong

      indexes
    end
    [ orders, nil ]
  end

  # The planned steps with the positions each waits for. A step waiting for one that cannot be followed is not followed
  # either, and is said with the rest of what cannot be.
  def self.placed(planned, cannot, orders, given, before: [])
    positions = {}
    next_position = before.empty? ? 0 : before.map(&:position).max + 1
    planned.filter_map do |planned_step|
      order = orders[planned_step[:index]]
      missing = order.filter_map { |at| at - before.size if at >= before.size && !positions.key?(at - before.size) }
      if missing.any?
        names = missing.map { |index| given_label(given[index], index) }.to_sentence
        cannot << "#{planned_step[:label]} was not followed either, since it waits for #{names}."
        next
      end

      positions[planned_step[:index]] = next_position
      next_position += 1
      planned_step.merge(waits_for: order.map { |at| at < before.size ? before[at].position : positions.fetch(at - before.size) })
    end
  end

  # The line the watch says when steps join it, on the card, in the thread and in direct messages.
  def self.steps_added_words(watch, labels, moved)
    limit = moved ? " It now watches for up to #{Chat::Watch::Shown.limit_label(watch)} from when it started." : ""
    "Now also following #{labels}.#{limit}"
  end

  # short is when the person's own limit stays and the added steps may not finish within it.
  def self.added_limit_words(watch, limit, moved, short: false)
    usual = limit.usual_seconds && Integrations::Capabilities::History.duration(limit.usual_seconds)
    took = usual ? " They usually take about #{usual}." : ""
    if short
      return "It keeps the limit of #{Chat::Watch::Shown.limit_label(watch)} from when it started that the person asked for, and the added " \
             "steps may not finish within it.#{took} Tell them so, and offer more time, which extend_watch gives once they ask."
    end
    return "Its limit of #{Chat::Watch::Shown.limit_label(watch)} from when it started already leaves them time.#{took}" unless moved

    "It now watches for up to #{Chat::Watch::Shown.limit_label(watch)} from when it started, to leave them time to finish.#{took}"
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
      step = as_capability(step)
      label = step["label"].to_s.strip.presence || "Step #{index + 1}"
      next plan_tool_step(step, label, reader, agent, planned, cannot, index) if step["tool"].present?

      key = key_for(step["capability"])
      next cannot << "#{label} cannot be followed, since #{step['capability'].presence || 'it names no capability, and that'} is not a read a watch can make." unless key

      arguments = arguments_for(step, key)
      next cannot << "#{label} needs what counts as done for it (done_when, failed_when or goal)." if Chat::Watch::Step.undecided?(step)

      usual, row = first_read(reader, key, arguments, step)
      signature = Chat::Watch::Step.signature(key, arguments) unless key == HISTORY
      usual ||= Chat::Watch::Step.usual_for(reader.workspace, signature)
      new_deploy = (baseline(reader, step, key, arguments) { reader.read(key, arguments).text } if Chat::Watch::Step.waits_for_deploy?(step, key))
      planned << { index: index, label: label, key: key, arguments: arguments, step: step, usual: usual, row: row, signature: signature, new_deploy: new_deploy }
    rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered => refused
      cannot << "#{label} cannot be followed. #{refused.message}"
    rescue Chat::Watch::Meter::Spent
      cannot << "#{label} was not read, since this watch's ceiling on reads for the hour is spent."
    end
    [ planned, cannot ]
  end

  # A step that reads with any tool Halon may read with in a chat, kept with the connection it reads through so a live
  # update from that connection wakes it, and with how long the same read usually took to reach done before.
  def self.plan_tool_step(step, label, reader, agent, planned, cannot, index = 0)
    return cannot << "#{label} needs what counts as done for it (done_when, failed_when or goal)." if Chat::Watch::Step.undecided?(step)

    tool = step["tool"].to_s
    arguments = tool_arguments(step)
    said = reader.read_tool(agent, tool, arguments)
    return cannot << "#{label} cannot be followed, since reading it failed: #{Chat::SecretFree.redacted(said.text).truncate(300)}" if said.failed?

    focus = step["focus"].to_s.strip
    if focus.present? && Chat::Watch::Step.at_path(said.text, focus).nil?
      return cannot << "#{label} cannot be followed, since its first reading holds nothing at #{focus}. Name a path the answer holds, such as data.status, or leave focus out."
    end

    signature = Chat::Watch::Step.signature(tool, arguments)
    waits = Chat::Watch::Step.waits_for_deploy?(step, Chat::Watch::Step::READ_TOOL)
    planned << { index: index, label: label, key: Chat::Watch::Step::READ_TOOL, tool: tool, arguments: arguments, step: step, signature: signature,
                 usual: Chat::Watch::Step.usual_for(reader.workspace, signature), row: connection_of(reader.workspace, tool, arguments),
                 new_deploy: (baseline(reader, step, Chat::Watch::Step::READ_TOOL, {}) { said.text } if waits) }
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered => refused
    cannot << "#{label} cannot be followed. #{refused.message}"
  rescue Chat::Watch::Meter::Spent
    cannot << "#{label} was not read, since this watch's ceiling on reads for the hour is spent."
  end

  def self.tool_arguments(step)
    step["arguments"].is_a?(Hash) ? step["arguments"].transform_keys(&:to_s).except(*Chat::Tools::FOR_PERSON) : {}
  end

  RUN_ARG = "run".freeze
  DEPLOYMENT_ARG = "deployment".freeze
  # What a capability takes on its own, which a step naming the capability as its tool may give among its arguments.
  LIFTED = [ Integrations::Capabilities::RESOURCE_ARG, Integrations::Capabilities::CONNECTION_ARG, "name", RUN_ARG ].freeze

  # A step naming a capability that reads as its tool is that capability, so it keeps the capability's own statuses, usual
  # duration and links.
  def self.as_capability(step)
    spec = Chat::Tools::Target.capability_spec(step["tool"])
    return step unless spec && !spec.writes

    given = tool_arguments(step)
    lifted = given.slice(*LIFTED).compact_blank.merge(step.slice(*LIFTED).compact_blank)
    step.except("tool").merge(lifted).merge("capability" => spec.tool_name, "arguments" => given.except(*LIFTED))
  end

  # The connection a read tool reads through, nil for Firefight's own tools or one whose connection cannot be told.
  def self.connection_of(workspace, tool_name, arguments)
    tool = Chat::Tools::Target.connection_tool(workspace, tool_name)
    tool && Chat::Tools::Target.environment_row_of(tool, arguments)
  rescue Integration::UnknownEnvironment
    nil
  end

  def self.first_read(reader, key, arguments, step)
    return [ nil, reader.route(key, arguments).environment_row ] unless key == HISTORY

    answer = reader.read(key, arguments)
    runs = Integrations::Capabilities::History.runs_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if runs.nil?

    refuse_other_kinds!(reader, arguments, step["name"]) if runs.none? { |run| run.called?(step["name"]) }
    [ Integrations::Capabilities::History.usual_seconds(runs, name: step["name"]), answer.call.environment_row ]
  end

  KINDS_SHOWN = 6

  # A history that holds runs, none of the name asked for, cannot follow that name, so it says at once which runs it does
  # hold rather than waiting for a run that never shows up there. An empty history may hold nothing yet.
  def self.refuse_other_kinds!(reader, arguments, name)
    return if name.blank?

    runs = Integrations::Capabilities::History.runs_of(reader.read(HISTORY, arguments.except("name")).result).to_a
    held = runs.filter_map { |run| run.name.to_s.strip.presence }.uniq(&:downcase)
    return if held.empty?

    shown = held.first(KINDS_SHOWN).map { |kind| %("#{kind}") }
    shown << "#{held.size - KINDS_SHOWN} more" if held.size > KINDS_SHOWN
    raise Conversation::Watches::Reader::Refused,
          "Its run history holds runs named #{shown.to_sentence}, none named \"#{name}\", so it cannot follow that. Follow it with a read " \
          "tool instead, such as the provider's general read of that run by its id."
  rescue Conversation::Watches::Reader::Unanswered
    nil
  end

  def self.create!(turn, title, limit, planned, purpose: nil, reads_per_hour: Chat::Watch.ceiling_for(nil, planned.size), reads_per_hour_asked: false)
    Chat::Watch.transaction do
      watch = Chat::Watch.create!(
        chat: turn.conversation.chat_record, workspace: turn.workspace, asker: turn.asker, title: title.truncate(Chat::Watch::TITLE_LIMIT),
        purpose: purpose&.truncate(Chat::Watch::PURPOSE_LIMIT), reads_per_hour: reads_per_hour, reads_per_hour_asked: reads_per_hour_asked,
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
      capability: planned_step[:key], arguments: planned_step[:arguments], tool_name: planned_step[:tool], read_signature: planned_step[:signature],
      integration_environment_id: planned_step[:row]&.id, run_name: given["name"].presence, run_ref: given["run"].presence,
      report_start: ActiveModel::Type::Boolean.new.cast(given["report_start"]) || false, done_when: given["done_when"].presence,
      failed_when: given["failed_when"].presence, goal: given["goal"].presence, usual_seconds: planned_step[:usual],
      focus: given["focus"].to_s.strip.presence, new_deploy: planned_step[:new_deploy],
      **(planned_step.key?(:waits_for) ? { waits_for: planned_step[:waits_for] } : {})
    }
  end

  # The deploy live when the step starts, or the digest of its first reading where the provider cannot tell deploys
  # apart, since a done can never be that reading.
  def self.baseline(reader, step, key, arguments, now: Time.current)
    target = Chat::Watch::Step.deploy_target(step, arguments)
    answer = deploys_answer(reader, target)
    deploys = answer && Integrations::Capabilities::Deploys.deploys_of(answer.result)
    provider = answer&.call&.environment_row&.integration&.name
    kept = Chat::Watch::Step.new_deploy_for(target, since: now, deploys: deploys, provider: provider)
    return kept if kept[Chat::Watch::Step::NewDeploy::IDENTITY]

    kept.merge(Chat::Watch::Step::NewDeploy::BASELINE_DIGEST => reading_digest(yield, step["focus"].to_s.strip.presence))
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered
    kept || Chat::Watch::Step.new_deploy_for(target, since: now, deploys: nil)
  end

  # The resource's deploys, read as the asker. nil when no resource is named.
  def self.deploys_answer(reader, target)
    resource = target[Chat::Watch::Step::NewDeploy::RESOURCE]
    return if resource.blank?

    reader.read(Integrations::Capabilities::DEPLOYS, target.slice(Chat::Watch::Step::NewDeploy::RESOURCE, Chat::Watch::Step::NewDeploy::CONNECTION))
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered
    nil
  end

  # The part judged, without secrets or the times that move every minute.
  def self.reading_digest(text, focus)
    Digest::SHA256.hexdigest(Chat::Watch::Step.focused(Chat::SecretFree.redacted(text.to_s), focus).gsub(CLOCK, ""))
  end

  def self.key_for(name) = Chat::Watch::Step.read_key(name)

  def self.arguments_for(step, key)
    extra = step["arguments"].is_a?(Hash) ? step["arguments"].transform_keys(&:to_s) : {}
    named = { Integrations::Capabilities::RESOURCE_ARG => step["resource"], Integrations::Capabilities::CONNECTION_ARG => step["connection"] }
    named["name"] = step["name"] if key == HISTORY
    extra.merge(named.compact_blank).except(*Chat::Tools::FOR_PERSON)
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

  # One check: each open step whose prerequisites all succeeded read once, its milestones said once, the jobs or steps
  # that moved said together in one line, and the watch ended when they are all over or its time ran out. A step whose
  # prerequisite went wrong is skipped rather than read. A watch another worker holds is left to it. Every read is
  # counted against the watch's ceiling, and one past it waits for the next hour.
  def self.check!(watch, now: Time.current)
    return unless watch.active? && watch.claim_check!(now)

    meter = Chat::Watch::Meter.new(watch.reads_left(now))
    read_all = true
    begin
      return time_out!(watch, now) if now >= watch.expires_at

      progress = []
      skip_blocked!(watch)
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

  # A step whose prerequisites have not all succeeded is not read at all, since what it reads would only show what came
  # before them.
  def self.check_step(watch, step, reader, agent, now, progress, reading: nil)
    return unless step.ready?
    return repair_lapsed!(watch, step) if step.repair_overdue?(now)
    return if step.repairing?
    return follow_run(watch, step, reader, now, progress) if step.history?

    gate = deploy_gate(watch, step, reader)
    return if gate && !gate_lets_read?(watch, step, gate)
    return take_reading(watch, step, reading, progress, now: now, gate: gate) if reading

    follow_reading(watch, step, reader, agent, progress, now: now, gate: gate)
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
    moved = step.progress!(part_states(run))
    step.summarized!(run_summary(run))
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
    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} succeeded#{took}.") if ended == Chat::Watch::Step::STATUS_SUCCEEDED
  end

  PARTS_NAMED = 2

  # Each job or step in the words its progress is said in. A run held as a whole, with no jobs or steps to say it of,
  # is said by its own name, so a deploy waiting for approval is heard rather than looking queued.
  def self.part_states(run)
    parts = Array(run.parts).map { |part| [ part.name.to_s, PART_STATES.fetch(part.status, Chat::Watch::Step::PART_WAITING) ] }
    return parts unless parts.empty? && run.status == Integrations::Capabilities::History::WAITING

    [ [ run.name.to_s.presence || "The run", Chat::Watch::Step::PART_HELD ] ]
  end

  # Where a run stands in a few words, for its row on the card, such as "build-images running, 4 of 7 done", rather than
  # every job it holds.
  def self.run_summary(run)
    history = Integrations::Capabilities::History
    parts = Array(run.parts)
    return "#{run.number ? "Run ##{run.number}" : 'The run'} is #{run.status}." if parts.empty?

    running = parts.select { |part| part.status == history::RUNNING }.map(&:name)
    held = parts.select { |part| part.status == history::WAITING }.map(&:name)
    done = parts.count { |part| part.status == history::SUCCEEDED }
    [ ("#{held.first(PARTS_NAMED).join(', ')} #{Chat::Watch::Step::PART_HELD}" if held.any?), ("#{running.first(PARTS_NAMED).join(', ')} running" if running.any?),
      "#{done} of #{parts.size} done" ].compact.join(", ")
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
    return listed unless carries_run?(call.arguments, run.id.to_s)

    answer = reader.read_call(call)
    found = Integrations::Capabilities::History.runs_of(answer.result)&.find { |each| each.id.to_s == run.id.to_s }
    found ? Detailed.new(run: found, environment_row: answer.call.environment_row) : listed
  rescue Conversation::Watches::Reader::Unanswered
    listed
  end

  # Whether a routed call asks for this run, as an argument of its own or inside a script a provider runs, such as
  # Cloudflare's, never as part of a longer id.
  def self.carries_run?(arguments, id)
    word = /(?<![\w-])#{Regexp.escape(id)}(?![\w-])/
    arguments.values.any? { |value| value.to_s == id || (value.is_a?(String) && value.match?(word)) }
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

  # A step whose read found nothing to follow is never left following nothing. The person is told, and Halon is asked to
  # repair it with a better read, in the chat the watch was started from, in a turn that only reads. One Halon already
  # repaired MAX_REPAIRS times is no longer followed instead.
  def self.ask_repair!(watch, step, reason)
    unless step.repairable? && !watch.workflow_step?
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
      "(#{step.arguments.except(*Chat::Tools::FOR_PERSON).to_json}).",
      step.repair_reason.presence,
      ("It was started for: #{watch.purpose}" if watch.purpose.present?),
      "Find a different read that shows it with the provider's read tools, its skill or search_docs, such as a GET request for that one run " \
      "by its id, and try it once. The same read again is refused. Then call repair_watch with this watch and step, the new read and why the old one showed nothing, so the same watch " \
      "follows it from here. When no read can show it, call repair_watch with give_up. Change nothing in this turn. Tell the person in a " \
      "sentence or two what you changed, or what you could not find."
    ].compact.join(" ")
  end

  # Halon gives an open step a better read, so the same watch follows it from here and says what changed. given is a
  # start_watch step with string keys, whose done and failed words default to the step's own. Answers what Halon tells
  # the person. The new read is tried as the watch's own asker, whom every later check reads as.
  def self.repair!(watch, step, given, why:)
    return reopen!(watch, step, given.except("reopen"), why: why) if ActiveModel::Type::Boolean.new.cast(given["reopen"])
    return Chat::Watch::NOTHING_TO_STOP unless watch.active?
    return "#{step.label} has already ended, so there is nothing to repair." unless Chat::Watch::Step::OPEN.include?(step.status)
    return give_up!(watch, step, why) if ActiveModel::Type::Boolean.new.cast(given["give_up"])
    return "#{step.label} was repaired #{Chat::Watch::Step::MAX_REPAIRS} times already. Call repair_watch with give_up instead." unless step.repairable?

    kept = { "done_when" => step.done_when, "failed_when" => step.failed_when, "goal" => step.goal }.compact
    asked = kept.merge(given.except("give_up")).merge("label" => step.label)
    return same_read_words(step) if same_read?(step.read_attributes, proposed_read(asked))

    meter = Chat::Watch::Meter.new(watch.reads_left)
    reader, agent = readers(watch.workspace, watch.asker, watch.conversation, meter)
    planned, cannot = plan([ asked ], reader, agent)
    watch.count_reads!(meter.count)
    return "Not repaired. #{cannot.join(' ')}" if planned.empty?

    order = reordered(watch, step, given)
    return "Not repaired. #{order}" if order.is_a?(String)

    before = step.read_attributes
    before_words = step.read_words
    read = read_of(planned.first).merge(order || {})
    read[:new_deploy] = repaired_deploy(step, read[:new_deploy])
    return "#{step.label} has already ended, so there is nothing to repair." unless step.repaired!(read)

    step.summarized!(step.deploy_start_words) if step.waits_for_deploy?

    tell!(watch, Chat::Watch::Update::KIND_REPAIRED,
          "Changed how I follow #{step.label}: #{change_words(before, before_words, step)}. #{why.to_s.strip.presence || 'The old read showed nothing to follow.'}")
    WatchCheckJob.perform_later(watch.id)
    "Repaired #{step.label} in #{Chat::Watch::Shown.named(watch)}. Tell the person in a sentence what you changed and why."
  end

  # How a step ended was shown to be wrong, by the person or by a reading Halon took, so the same watch follows it again
  # from the start, with a new read when given, and the watch goes again when it had ended. Steps skipped because of it
  # are followed again too, and skipped once more if what they wait for still went wrong. A watch a person stopped
  # stays stopped. Answers what Halon tells the person.
  def self.reopen!(watch, step, given, why:)
    if watch.status == Chat::Watch::STATUS_STOPPED
      return "#{Chat::Watch::Shown.name(watch)} was stopped, so it is not reopened. Start a new watch when the person wants it followed again."
    end
    return "#{step.label} has not ended, so there is nothing to reopen. Call repair_watch without reopen to change how it is followed." unless step.over?

    until_at = watch.reopened_until
    return "#{Chat::Watch::Shown.name(watch)} started a day ago, which is as long as a watch goes. Start a new watch instead." unless until_at

    read, wrong = reopened_read(watch, step, given)
    return "Not reopened. #{wrong}" if wrong
    return "#{Chat::Watch::Shown.name(watch)} could not be reopened just now. Try again." unless watch.active? || watch.reopen!(until_at)
    return "#{step.label} is already being followed again." unless step.reopened!(read)

    watch.steps.reload.select { |each| each.status == Chat::Watch::Step::STATUS_SKIPPED }.each(&:reopened!)
    step.summarized!(step.deploy_start_words) if step.waits_for_deploy?
    # Halon says it in its own answer, so it is not heard again at the next turn.
    tell!(watch, Chat::Watch::Update::KIND_REOPENED, "Reopened #{step.label}: #{why.to_s.strip.presence || 'How it ended was wrong.'}").update_columns(told_at: Time.current)
    WatchCheckJob.perform_later(watch.id)
    "Reopened #{step.label} in #{Chat::Watch::Shown.named(watch)}, which follows it again from now. Tell the person in a sentence why how it ended was wrong, " \
      "and that the watch reports again."
  end

  # The read a reopened step makes: the new one when a read is given, tried once as the asker, or its own.
  def self.reopened_read(watch, step, given)
    order = reordered(watch, step, given)
    return [ nil, order ] if order.is_a?(String)
    return [ order || {}, nil ] if proposed_read(given.merge("label" => step.label)).nil?

    kept = { "done_when" => step.done_when, "failed_when" => step.failed_when, "goal" => step.goal }.compact
    meter = Chat::Watch::Meter.new(watch.reads_left)
    reader, agent = readers(watch.workspace, watch.asker, watch.conversation, meter)
    planned, cannot = plan([ kept.merge(given).merge("label" => step.label) ], reader, agent)
    watch.count_reads!(meter.count)
    return [ nil, cannot.join(" ") ] if planned.empty?

    [ read_of(planned.first).merge(order || {}), nil ]
  end

  # The steps a repaired or reopened step waits for when given, as positions of steps before it. Nil when none are
  # given, so it keeps its own, and a sentence when one cannot be.
  def self.reordered(watch, step, given)
    refs = given[Chat::Watch::SPEC_KEYS[:waits_for]]
    return if refs.nil?

    steps = watch.steps.to_a
    at = steps.index(step)
    indexes, wrong = Chat::Watch::Step.prerequisites_named(step.label, Array(refs).map(&:to_s).compact_blank, steps.map(&:label), at)
    wrong || { waits_for: indexes.map { |index| steps[index].position } }
  end

  # A repair keeps the baseline unless the new read follows another resource. The new read's first reading replaces the
  # old one's, which says nothing about it.
  def self.repaired_deploy(step, fresh)
    return fresh unless step.waits_for_deploy?
    return step.new_deploy if fresh.nil?

    keys = Chat::Watch::Step::NewDeploy
    moved = [ keys::RESOURCE, keys::CONNECTION, keys::ENVIRONMENT ].any? { |key| fresh[key].present? && !fresh[key].to_s.casecmp?(step.new_deploy[key].to_s) }
    return fresh if moved

    named = [ keys::COMMIT, keys::TAG, keys::BRANCH ]
    target = fresh.slice(*named).presence ? fresh.slice(*named, keys::REPOSITORY) : step.new_deploy.slice(*named, keys::REPOSITORY, keys::TAG_COMMIT, keys::TAG_UNREAD)
    step.new_deploy.except(*named, keys::REPOSITORY, keys::TAG_COMMIT, keys::TAG_UNREAD, keys::BASELINE_DIGEST, keys::LIVE_SEEN).merge(target)
        .merge(fresh.slice(keys::BASELINE_DIGEST))
  end

  # The read a repair asks for, as a step keeps it, worked out without reading. nil when it names no read a watch makes.
  def self.proposed_read(given)
    step = as_capability(given)
    focus = step["focus"].to_s.strip.presence
    named = { run_name: step["name"].presence, run_ref: step["run"].presence, focus: focus }
    return { capability: Chat::Watch::Step::READ_TOOL, tool_name: step["tool"].to_s, arguments: tool_arguments(step), **named } if step["tool"].present?

    key = key_for(step["capability"])
    key && { capability: key, tool_name: nil, arguments: arguments_for(step, key), **named }
  end

  def self.same_read?(before, after)
    after.present? && %i[capability tool_name run_name run_ref focus].all? { |attribute| before[attribute].to_s == after[attribute].to_s } &&
      comparable(before[:arguments]) == comparable(after[:arguments])
  end

  def self.same_read_words(step)
    "Not repaired. That is the read #{step.label} already makes (#{step.read_words}), and it is what showed nothing to follow, so " \
      "reading it again changes nothing. Find a different read, such as the provider's general read of that one run by its id, a " \
      "focus on the part of the answer that matters, or another tool its skill names. When no read can show it, call repair_watch with give_up."
  end

  # What a repair changed, as the person reads it: another read altogether, or the same read with the arguments that differ.
  def self.change_words(before, before_words, step)
    after = step.read_attributes
    return "I now read #{step.read_words} instead of #{before_words}" if before.values_at(:capability, :tool_name) != after.values_at(:capability, :tool_name)

    was = comparable(before[:arguments])
    now = comparable(after[:arguments])
    changed = (was.keys | now.keys).sort.filter_map do |key|
      "#{key} #{now[key].presence || 'left out'} instead of #{was[key].presence || 'none'}" unless was[key] == now[key]
    end
    changed += { run_name: "name", run_ref: "run", focus: "focus" }.filter_map do |attribute, word|
      "#{word} #{after[attribute].presence || 'left out'} instead of #{before[attribute].presence || 'none'}" unless before[attribute].to_s == after[attribute].to_s
    end
    "I still read with #{step.read_tool? ? step.tool_name : Chat::Watch::Step.read_label(step.spec)}, now with #{changed.to_sentence}"
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
  def self.follow_reading(watch, step, reader, agent, progress, now: Time.current, gate: nil)
    sources_before!(step, reader) if logs?(step) && step.waits? && step.sources_before.nil?
    answer = step.read_tool? ? reader.read_tool(agent, step.tool_name, step.arguments) : reader.read(step.capability, read_arguments(step))
    raise Conversation::Watches::Reader::Unanswered, answer.text.truncate(300) if answer.failed?

    take_reading(watch, step, answer.text, progress, now: now, gate: gate)
  end

  def self.logs?(step) = step.capability == Integrations::Capabilities::LOGS

  # A logs step that waits for others reads only the lines logged once they finished.
  def self.read_arguments(step)
    from = logs?(step) && step.counts_from
    from ? step.arguments.merge("start" => from.utc.iso8601) : step.arguments
  end

  # The sources already logging in the minutes before its prerequisites began, read once with none of its filters, so
  # whoever judges its readings can tell an old instance from a new one.
  def self.sources_before!(step, reader)
    began = step.runs_from || step.counts_from
    given = step.arguments.slice(Integrations::Capabilities::RESOURCE_ARG, Integrations::Capabilities::CONNECTION_ARG, "stream")
                .merge("start" => (began - Chat::Watch::Step::SOURCES_BEFORE).utc.iso8601, "end" => began.utc.iso8601, "limit" => Chat::Watch::Step::SOURCES_LIMIT)
    answer = reader.read(step.capability, given)
    step.sources_before!(answer.failed? ? [] : Chat::Watch::Step.log_sources(answer.text))
  rescue Conversation::Watches::Reader::Refused, Conversation::Watches::Reader::Unanswered
    step.sources_before!([])
  end

  # nil for a step that waits for no deploy, or whose provider cannot tell deploys apart, which its reading decides.
  def self.deploy_gate(watch, step, reader)
    return unless step.deploy_identity?

    resolve_tag!(step, reader) if step.unresolved_tag
    answer = deploys_answer(reader, step.new_deploy)
    deploys = answer && Integrations::Capabilities::Deploys.deploys_of(answer.result)
    raise Conversation::Watches::Reader::Unanswered, "the deploys of #{step.deploy_resource} could not be read" if deploys.nil?

    step.deploy_gate(deploys)
  end

  # A tag a release has not pushed yet is asked again next check. One no code host can read is matched by the deploys'
  # own tag or version.
  def self.resolve_tag!(step, reader)
    keys = Chat::Watch::Step::NewDeploy
    step.tag_resolved!(reader.commit_of(step.new_deploy[keys::REPOSITORY].presence || step.deploy_resource, step.unresolved_tag))
  rescue Conversation::Watches::Reader::Refused => refused
    step.tag_unresolvable!(refused.message)
  rescue Conversation::Watches::Reader::Unanswered
    nil
  end

  # Before the new deploy starts the step's reading only shows the old one, so it is not read. A newest deploy that was
  # cancelled or replaced is waited past, and one that failed is told at once while a newer one may still come.
  def self.gate_lets_read?(watch, step, gate)
    step.summarized!(gate.words)
    keys = Chat::Watch::Step::NewDeploy
    case gate.state
    when keys::WAITING, keys::CANCELLED then false
    when keys::FAILED
      finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, gate.words)
      false
    when keys::FAILED_FOR_NOW
      tell!(watch, Chat::Watch::Update::KIND_PART_FAILED, standing(watch, step.deploy_failure)) if step.deploy_failed!(gate)
      false
    else
      step.deploy_failure_passed!
      deploy = gate.deploy
      if step.started_told_at.nil? && step.started!(run_id: deploy.id || deploy.short, at: deploy.started_at)
        tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} started.") if step.report_start
      end
      true
    end
  end

  # Judged by the workspace's quick model answering the step's question over its recent readings, into not started,
  # running, done, failed or nothing to follow, with the jobs or steps it lists, its page and a few words on where it
  # stands. Each reading that changed is judged, and one that stayed the same every JUDGE_STEADY_EVERY. A reading that
  # shows it begun moves the step to running, a job or step in it that failed is said at once with why, and a first
  # reading with nothing to follow is handed back to Halon to repair. Only where no model may answer does the text the
  # step was given decide, as words the reading holds.
  def self.take_reading(watch, step, text, progress, now: Time.current, gate: nil)
    text = Chat::Watch::Step.focused(Chat::SecretFree.redacted(text), step.focus)
    digest = Digest::SHA256.hexdigest(text.gsub(CLOCK, ""))
    changed = digest != step.last_digest
    step.seen!(digest: digest, state: text, now: now, kept: true)
    opened = gate&.open? && step.deploy_live_seen!(gate.deploy)
    return unless changed || opened || step.judge_again?(now)

    first = step.judged_at.nil? && step.status == Chat::Watch::Step::STATUS_WAITING
    model = judge(watch)
    return deploy_by_gate(watch, step, gate) if !model && gate
    return (by_words(watch, step, text) unless step.unchanged_since_baseline?(digest)) unless model

    judged = held_back(step, judged_reading(model, step, now, gate: gate), gate, digest)
    return unless judged

    judged = no_error_line(step, judged, text)

    step.judged!(now)
    step.linked!(judged.link)
    if judged.state == FirefightAi::Schemas::WatchReading::NOTHING
      return ask_repair!(watch, step, "The first reading of #{step.label} showed nothing to follow. #{judged.said}".strip) if first

      return
    end

    step.summarized!(judged.said)
    moved = step.progress!(judged.parts.filter_map { |name, state| [ name, READING_PARTS[state] ] if READING_PARTS[state] }, said: Chat::Watch::Step::PART_SAID)
    reading_part_failed(watch, step, judged, model)
    step.failure_cleared! unless judged.state == FirefightAi::Schemas::WatchReading::FAILED
    case judged.state
    when FirefightAi::Schemas::WatchReading::DONE then finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, judged.said)
    when FirefightAi::Schemas::WatchReading::FAILED then reading_failed(watch, step, judged.said, now)
    when FirefightAi::Schemas::WatchReading::RUNNING
      reading_started(watch, step)
      progress << "#{step.label}: #{moved.join(', ')}." if moved.any?
      tell!(watch, Chat::Watch::Update::KIND_SLOW, slow_words(step, now)) if step.slow?(now) && step.slow_told!
    end
  end

  # A reading that shows a step failed ends it only once the next reading shows the same, so one misread reading never
  # ends a watch. Until then it keeps going and its row says what the reading showed.
  def self.reading_failed(watch, step, said, now)
    return finish_reading(watch, step, Chat::Watch::Step::STATUS_FAILED, said) if step.failure_seen_at

    step.summarized!(said)
    step.failure_seen!(now)
  end

  # Logs say a step failed only in a line at error level or worse. Where the lines carry their level, one with none at
  # that level is not a failure, whatever a warning or an instance stopping cleanly says, so the step keeps going.
  def self.no_error_line(step, judged, text)
    return judged unless judged.state == FirefightAi::Schemas::WatchReading::FAILED && logs?(step) && errorless?(text)

    judged.with(state: step.running? ? FirefightAi::Schemas::WatchReading::RUNNING : FirefightAi::Schemas::WatchReading::NOT_STARTED)
  end

  def self.errorless?(text)
    levels = Integrations::Telemetry.levels_in(text)
    levels.any? && levels.none? { |level| Integrations::Telemetry.error_level?(level) }
  end

  # With no model to judge, the new deploy being live is enough.
  def self.deploy_by_gate(watch, step, gate)
    finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, gate.words) if gate.open?
  end

  # Done before the new deploy is live, or an end judged on a reading unchanged since the watch began, is about the
  # deploy already live then, so the step keeps going.
  def self.held_back(step, judged, gate, digest)
    return judged unless judged && step.waits_for_deploy?

    reading = FirefightAi::Schemas::WatchReading
    ending = [ reading::DONE, reading::FAILED ].include?(judged.state)
    early = (judged.state == reading::DONE && gate && !gate.open?) || (ending && step.unchanged_since_baseline?(digest))
    return judged unless early

    said = gate ? gate.words : step.no_identity_words
    judged.with(state: step.running? ? reading::RUNNING : reading::NOT_STARTED, said: said)
  end

  # nil when the model could not answer this time, which the next check asks again.
  def self.judged_reading(model, step, now, gate: nil)
    model.reading(question: reading_goal(step, gate), readings: step.recent_readings, so_far: step.running? ? "running" : "not started",
                  steady: steady_words(step, now))
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::OutOfCredit => error
    Rails.logger.warn({ event: "watch.reading_unjudged", step_id: step.id, error: error.class.name }.to_json)
    nil
  end

  # A job or step the reading shows failed while the rest goes on is said once, with why from the readings.
  def self.reading_part_failed(watch, step, judged, model)
    name, = judged.parts.find { |_name, state| state == FirefightAi::Schemas::WatchReading::PART_FAILED }
    return if name.nil? || judged.state == FirefightAi::Schemas::WatchReading::FAILED || step.failed_part_told_at || !step.part_failed!(name)

    why = begin
      model.why_failed(what: "#{step.label}, #{name}", evidence: step.recent_readings.last&.last.to_s.truncate(EVIDENCE_LIMIT))
    rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::OutOfCredit
      nil
    end
    tell!(watch, Chat::Watch::Update::KIND_PART_FAILED, standing(watch, "#{step.label}: #{name} failed. #{why || 'The reading does not say why.'}".squish))
  end

  # With no model to judge, the words the step was given decide, read as text the reading holds.
  def self.by_words(watch, step, text)
    failed = says?(text, step.failed_when) && !(logs?(step) && errorless?(text))
    return reading_failed(watch, step, excerpt(text, step.failed_when), Time.current) if failed

    step.failure_cleared!
    finish_reading(watch, step, Chat::Watch::Step::STATUS_SUCCEEDED, nil) if says?(text, step.done_when)
  end

  # How long a reading has stayed the same, for a condition that names a time. nil when it just changed.
  def self.steady_words(step, now)
    steady = step.steady_since && now - step.steady_since
    "The reading has stayed the same for #{Integrations::Capabilities::History.duration(steady)}." if steady && steady >= Chat::Watch::CHECK_EVERY
  end

  LOG_LEVEL_QUESTION = "It failed only on a log line at error level or worse, by the level the line carries. A warning or an info " \
                       "line, and an instance stopping with exit code 0, never mean it failed.".freeze

  # What done means for a reading, for a step waiting for a new deploy which deploy that is, for a step waiting for
  # others what came after them, and for logs that only an error-level line fails it.
  def self.reading_goal(step, gate = nil)
    [ step.goal.presence || "#{step.label} finishes.", ("It is done when the readings show #{step.done_when}." if step.done_when.present?),
      ("It failed when the readings show #{step.failed_when}." if step.failed_when.present?),
      ("The deploy it waits for: #{gate.words}" if gate), step.deploy_question, step.order_question,
      (LOG_LEVEL_QUESTION if logs?(step)) ].compact.join(" ")
  end

  def self.reading_started(watch, step)
    return unless step.started_told_at.nil? && step.started!(run_id: step.followed_run_id, at: Time.current)

    tell!(watch, Chat::Watch::Update::KIND_MILESTONE, "#{step.label} started.") if step.report_start
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
      # The failed run's own build log where the provider reads one by id, never only the newest.
      given[DEPLOYMENT_ARG] = run.id.to_s if stream == build && run.id.present?
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

    FirefightAi::WatchJudge.new(watch.workspace, inferable: watch, member: (watch.asker if watch.asker.is_a?(WorkspaceMembership)))
  end

  # Whether every step is over is decided over the steps as they were read, so steps added meanwhile keep it going. What
  # waits for a step that went wrong is skipped first, so the end names it.
  def self.conclude!(watch)
    skip_blocked!(watch)
    added = Chat::Watch.where(id: watch.id).pick(:steps_added_at)
    steps = watch.steps.reload.to_a
    failed = steps.find { |step| step.status == Chat::Watch::Step::STATUS_FAILED }
    return fail_on!(watch, failed) if failed
    return unless steps.all?(&:over?)

    followed = steps.select { |step| step.status == Chat::Watch::Step::STATUS_SUCCEEDED }
    if followed.empty?
      return finish!(watch, Chat::Watch::STATUS_STOPPED, "I stopped #{Chat::Watch::Shown.named(watch)}, since none of it can be followed any more.",
                     end_reason: "None of it can be followed any more.", steps_added_at: added)
    end

    took = Integrations::Capabilities::History.duration(Time.current - watch.created_at)
    skipped = steps.count { |step| step.status == Chat::Watch::Step::STATUS_SKIPPED }
    lost = lost_words(steps.size - followed.size - skipped, skipped)
    happened = "Done in #{took}.#{lost}"
    said = verdict(watch, happened, offer: false)
    finish!(watch, Chat::Watch::STATUS_SUCCEEDED, with_standing(watch, happened, said), end_reason: [ "Took #{took}.#{lost}", said ].compact.join(" "),
            steps_added_at: added)
  end

  def self.lost_words(lost, skipped)
    return "" unless lost.positive?

    skips = skipped.positive? ? ", so #{skipped} that wait#{'s' if skipped == 1} for #{lost > 1 ? 'them' : 'it'} #{skipped > 1 ? 'were' : 'was'} skipped" : ""
    " #{lost} step#{'s' if lost > 1} could not be followed#{skips}."
  end

  # Ends it failed on this step. A step skipped because of this one is named after it, since what the person wanted
  # waited on it too. The card's line names the step, why it failed in the plain words its reason was asked in, and where
  # that leaves the goal.
  def self.fail_on!(watch, step, **guards)
    took = step.seconds_taken && " after #{Integrations::Capabilities::History.duration(step.seconds_taken)}"
    skipped = skipped_after(watch, step)
    skips = skipped.any? ? " #{skipped.map(&:label).to_sentence} #{skipped.size > 1 ? 'were' : 'was'} skipped, since #{skipped.size > 1 ? 'they wait' : 'it waits'} for it." : ""
    happened = "#{step.label} failed#{took}, so I stopped #{Chat::Watch::Shown.named(watch)}. #{step.reason.presence || 'It did not say why.'}#{skips}"
    said = verdict(watch, happened)
    finish!(watch, Chat::Watch::STATUS_FAILED, with_standing(watch, happened, said), end_reason: [ "#{step.label} failed#{took}.", step.reason.presence, said ].compact.join(" "), **guards)
  end

  # Skips what waits for a step that failed or could not be followed, down the chain, each said on the card once.
  def self.skip_blocked!(watch)
    loop do
      skipped = watch.open_steps.select { |step| (blocker = step.blocked_by) && step.skipped!(step.skip_words(blocker)) }
      break if skipped.empty?
    end
  end

  # The steps skipped because of this one, directly or down the chain.
  def self.skipped_after(watch, step)
    words = "Skipped because #{step.label} failed."
    watch.steps.select { |each| each.status == Chat::Watch::Step::STATUS_SKIPPED && each.reason == words }
  end

  # What happened, then where that leaves what the person wanted, when the watch was started for a purpose. Where
  # something went wrong it also offers the next step, never on a good end. Said by a model from what happened and what
  # each step that ended showed, and the purpose itself when Halon is not available.
  def self.standing(watch, happened, offer: true) = with_standing(watch, happened, verdict(watch, happened, offer: offer))

  def self.with_standing(watch, happened, said)
    return happened if watch.purpose.blank?

    [ happened, said || "This was for: #{watch.purpose}" ].join(" ")
  end

  # Where what happened leaves the goal, in a sentence judged against what each step that ended showed, or nil when the
  # watch has no purpose or Halon cannot say.
  def self.verdict(watch, happened, offer: true)
    return if watch.purpose.blank?

    judge(watch)&.standing(purpose: watch.purpose, happened: happened, offer: offer, evidence: evidence(watch)).presence
  rescue FirefightAi::TransientError, FirefightAi::TerminalError, FirefightAi::OutOfCredit
    nil
  end

  # What each step that ended showed, in the words its reading was judged in, with how far a run got where nothing was
  # said. Seen in a real chat, a watch whose rollout step saw every instance on the new version was judged to show
  # nothing, since all the verdict was told was how long it took.
  def self.evidence(watch)
    Chat::Watch::Step.where(watch_id: watch.id).order(:position).includes(:watch).select(&:over?).map do |step|
      shown = [ Chat::Watch::Shown.step_state(step), (step.summary if step.reason.blank?) ].compact_blank.join(" ")
      "#{step.label}: #{shown}"
    end
  end

  # Only while the limit is still past, since steps added meanwhile may have moved it.
  def self.time_out!(watch, now = Time.current)
    return if deploy_failed_out!(watch, now)

    state = watch.open_steps.map { |step| "#{step.label}: #{step.ready? ? step.last_state.presence || 'nothing seen yet' : step.prerequisites_words}" }.join(" ")
    took = Integrations::Capabilities::History.duration(watch.expires_at - watch.created_at)
    happened = "I stopped #{Chat::Watch::Shown.named(watch)} after #{took}, its time limit. Last I saw: #{state.truncate(600)}"
    said = verdict(watch, happened)
    ended = finish!(watch, Chat::Watch::STATUS_TIMED_OUT, with_standing(watch, happened, said),
                    end_reason: [ "Reached its time limit after #{took}.", said ].compact.join(" "), expired_by: now)
    skip_unstarted!(watch) if ended
    ended
  end

  # A step still waiting for others when the time ran out never started, so it is skipped rather than left open, naming
  # the step it waited for, or the one that held that step up.
  def self.skip_unstarted!(watch)
    watch.steps.reload.reject(&:over?).reject(&:ready?).each do |step|
      held = step.prerequisites.find { |each| each.status == Chat::Watch::Step::STATUS_SKIPPED }
      step.skipped!(held&.reason.presence || "Skipped because #{step.waiting_on.map(&:label).to_sentence} did not finish within the time limit.")
    end
  end

  # A step whose new deploy failed with nothing newer by the time limit ends the watch failed, rather than timed out.
  def self.deploy_failed_out!(watch, now)
    step = watch.open_steps.find(&:deploy_failure)
    return false unless step

    reason = "#{step.deploy_failure} Nothing newer went out before the time limit."
    step.finished!(Chat::Watch::Step::STATUS_FAILED, reason: reason)
    skip_blocked!(watch)
    fail_on!(watch, step.reload, expired_by: now)
  end

  def self.finish!(watch, status, outcome, end_reason: nil, stopped_by: nil, **guards)
    return false unless watch.finish!(status, outcome: outcome, end_reason: end_reason, stopped_by: stopped_by, **guards)

    tell!(watch, Chat::Watch::Update::KIND_ENDED, outcome, ended_as: status)
    true
  end

  # Stops it for this person, saying so once. Returns why not, or nil.
  def self.stop!(watch, by:)
    blocked = watch.stop_blocked_reason(by)
    return blocked if blocked

    who = by.try(:actor_display_name) || "Someone"
    member = by if by.is_a?(WorkspaceMembership)
    stopped = finish!(watch, Chat::Watch::STATUS_STOPPED, "#{who} stopped #{Chat::Watch::Shown.named(watch)}.", end_reason: "Stopped by #{who}.", stopped_by: member)
    return Chat::Watch::NOTHING_TO_STOP unless stopped

    nil
  end

  # Stop pressed on a watch's card on the platform, by whoever pressed it. The watch's end is said where it reports, as
  # any stop is, which redraws its cards. A message pressed that is none of them, such as one a watch posted before it
  # kept a card, or a card pressed after the watch had ended, is redrawn the same way. Returns why it was not stopped, or nil.
  def self.stop_pressed!(update, by:, channel_id:, message_id:)
    watch = update.watch
    blocked = stop!(watch, by: by)
    watch.reload
    redraw_pressed(watch, update, channel_id, message_id) unless watch.active? || (blocked.nil? && watch.card_at?(channel_id, message_id))
    blocked
  end

  def self.redraw_pressed(watch, update, channel_id, message_id)
    return if channel_id.blank? || message_id.blank?

    adapter = WorkspaceAdapter.for(watch.workspace)
    adapter.update_watch_card(channel_id: channel_id, message_id: message_id,
                              card: card(watch, update, direct: adapter.direct_conversation?(channel_id: channel_id)))
  rescue AdapterError => error
    Rails.logger.warn({ event: "watch.stop_unshown", watch_id: watch.id, update_id: update.id, error: error.class.name }.to_json)
  end

  # A live update about a connection a watch reads through wakes it now rather than at the next sweep. A run sends an
  # event per job it finishes, so a watch checked within unless_checked_within is passed over, and the sweep catches
  # what came after.
  def self.wake!(environment_row, unless_checked_within: nil)
    watches = Chat::Watch.reading_through(environment_row)
    watches = watches.not_checked_within(unless_checked_within) if unless_checked_within
    watches.pluck(:id).each { |id| WatchCheckJob.perform_later(id) }
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
    steps = watch.open_steps.reject(&:repairing?).select { |step| step.ready? && reads_the_same?(step, tool_name, arguments) }
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
    arguments.to_h.deep_stringify_keys.except(*Chat::Tools::FOR_PERSON).transform_values { |value| value.is_a?(Enumerable) ? value.to_json : value.to_s }
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

  # Says one line: kept with the chat and drawn on its page, and moving the watch's card where it reports, in the chat's
  # thread when it has one, and in the asker's direct messages, unless the thread already is one with them. The end is
  # also said in a short line of its own beside each card, since editing a message notifies nobody.
  def self.tell!(watch, kind, text, ended_as: nil)
    update = watch.updates.create!(kind: kind, text: Chat::SecretFree.redacted(text), ended_as: ended_as)
    return workflow_told!(watch, update) if watch.workflow_step?

    Conversation::LiveDelivery.watch_moved(watch.conversation)
    adapter = WorkspaceAdapter.for(watch.workspace)
    shown = Chat::Watch.includes(:steps).find(watch.id)
    places(shown, adapter).each do |place|
      show_card(shown, update, adapter, place)
      say_end(shown, update, adapter, place) if kind == Chat::Watch::Update::KIND_ENDED && end_told?(shown)
    end
    update
  end

  def self.places(watch, adapter)
    conversation = watch.conversation
    in_thread = conversation.thread_id.present?
    user_id = watch.asker.try(:platform_user_id)
    [
      (Place.new(key: Chat::Watch::PLACE_THREAD, channel_id: conversation.channel_id, thread_id: conversation.thread_id) if in_thread),
      (Place.new(key: Chat::Watch::PLACE_DIRECT, channel_id: user_id, thread_id: nil) unless user_id.blank? || (in_thread && adapter.direct_conversation?(channel_id: conversation.channel_id)))
    ].compact
  end

  # Redraws the place's card from how the watch stands now, or posts it the first time. Posting is claimed first, so two
  # workers never post it twice, and a post that failed lets go of its claim for the next line to try.
  def self.show_card(watch, update, adapter, place)
    if (at = watch.card_in(place.key))
      return adapter.update_watch_card(channel_id: at.first, message_id: at.last, card: card(watch, update, direct: place.direct?))
    end
    return unless watch.claim_card!(place.key)

    drawn = card(watch, update, direct: place.direct?)
    posted = adapter.post_watch_card(channel_id: place.channel_id, thread_id: place.thread_id, card: drawn)
    return watch.card_unclaimed!(place.key) unless posted.is_a?(Hash) && posted[:message_id]

    unless watch.card_posted!(place.key, channel_id: posted[:channel_id], message_id: posted[:message_id])
      return adapter.delete_message(channel_id: posted[:channel_id], message_id: posted[:message_id])
    end
    # What another worker said while this one posted found no card to edit, so the card is drawn again when it moved.
    now = card(watch, update, direct: place.direct?)
    adapter.update_watch_card(channel_id: posted[:channel_id], message_id: posted[:message_id], card: now) if now != drawn
  rescue AdapterError => error
    watch.card_unclaimed!(place.key) unless at
    Rails.logger.warn({ event: "watch.untold", watch_id: watch.id, update_id: update.id, error: error.class.name }.to_json)
  end

  def self.say_end(watch, update, adapter, place)
    adapter.post_watch_end(channel_id: place.channel_id, thread_id: place.thread_id, card: card(watch, update, direct: place.direct?))
  rescue AdapterError => error
    Rails.logger.warn({ event: "watch.untold", watch_id: watch.id, update_id: update.id, error: error.class.name }.to_json)
  end

  # Whoever asked for it and stopped it themselves sees the card change and needs no word of it.
  def self.end_told?(watch)
    !(watch.status == Chat::Watch::STATUS_STOPPED && watch.asker_type == WorkspaceMembership.name && watch.stopped_by_id == watch.asker_id)
  end

  # How the watch stands now, as its card shows it. direct is a card in the asker's direct messages, which offers to
  # open a dashboard chat.
  def self.card(watch, update, direct:)
    conversation = watch.conversation
    Card.new(watch_id: watch.id, update_id: update.id, status: watch.status, state: Chat::Watch::Shown.state_word(watch),
             what: Chat::Watch::Shown.what(watch), why: Chat::Watch::Shown.why(watch), link: Chat::Watch::Shown.link(watch),
             conversation_id: (conversation.id if direct && conversation.personal?))
  end

  # A watch a workflow's step started reports to nobody as it goes. The run's page shows its lines, and its end goes back
  # to the step, which carries the run on.
  def self.workflow_told!(watch, update)
    return update unless update.kind == Chat::Watch::Update::KIND_ENDED

    record = watch.workflow_step
    DefinedWorkflow.deliver_for_record!(record, DefinedWorkflow::Steps::Watch::HANDED_OFF,
                                        { "status" => update.ended_as || watch.status, "outcome" => update.text })
    update
  end

  # The mark beside a line on the chat's page. A line that said how it ended keeps that, also once a reopened watch goes on.
  def self.tone(watch, update)
    update.kind == Chat::Watch::Update::KIND_ENDED ? ENDED_TONES.fetch(update.ended_as || watch.status, TONE_DONE) : update.kind
  end

  REOPEN_NOTE = "When the person, or a reading you take, shows a watch ended wrongly, such as a step judged on what was there " \
                "before, reopen that step with repair_watch and reopen true rather than repeating how it ended.".freeze

  # What Halon hears at its next turn: each line its watches said since, and the ones still going, once each.
  def self.untold_note(chat)
    updates = Chat::Watch::Update.joins(:watch).where(chat_watches: { chat_id: chat.id }).untold.includes(:watch).order(:created_at).to_a
    return nil if updates.empty?

    Chat::Watch::Update.where(id: updates.map(&:id)).update_all(told_at: Time.current)
    Chat::Watch.where(chat_id: chat.id, id: updates.map(&:watch_id)).untold.update_all(told_at: Time.current)
    lines = updates.map { |update| "- #{Chat::Watch::Shown.name(update.watch)}#{" (for: #{update.watch.purpose})" if update.watch.purpose.present?}: #{update.text}" }
    ended = updates.any? { |update| update.kind == Chat::Watch::Update::KIND_ENDED } ? "\n#{REOPEN_NOTE}" : ""
    "What your watches said since you last looked, already told to the person. A reading you take now beats any of it:\n#{lines.join("\n")}#{ended}"
  end
end
