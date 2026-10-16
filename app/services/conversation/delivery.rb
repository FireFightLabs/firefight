# What the agent says while it is answering someone. The platform decides how it looks.
class Conversation::Delivery
  FAILED = "Something went wrong on my side, so I did not finish that one. Ask me again.".freeze
  UNREADABLE = "The model sent back a reply I could not read, so I did not finish that one.".freeze
  ASK_AGAIN = "Ask me again.".freeze
  ASK_AGAIN_OR_PICK = "Ask me again, or pick another model for this chat.".freeze
  # The last line of an answer a lost turn was writing, so what it said so far never reads as finished.
  INTERRUPTED_HERE = "Interrupted here.".freeze

  # Saved in the chat and said where the person asked, so a turn that could not finish is never a silence. What Halon did
  # before it stopped follows the reason, so the people it was helping carry on from there.
  def self.give_up!(conversation, text)
    text = with_where_it_stopped(conversation, text)
    conversation.note!(text)
    conversation.reply_failed!
    self.for(conversation).failed!(text)
  end

  # Another model is offered only where the chat has a picker, a person's own chat with more than one model to choose.
  def self.unreadable(conversation)
    picks = conversation.personal? && conversation.model_menu.offers_choice?
    "#{UNREADABLE} #{picks ? ASK_AGAIN_OR_PICK : ASK_AGAIN}"
  end

  def self.with_where_it_stopped(conversation, text)
    [ text, Chat::StoppedNote.since_last_answer(conversation.chat) ].compact.join("\n\n")
  end

  # turn_started_at is when the turn began, which a chart of one of its calls was drawn after.
  def self.for(conversation, turn_started_at: Time.current)
    return Conversation::QuietDelivery.new(conversation) if conversation.mcp?
    return Conversation::IssueDelivery.new(conversation) if conversation.issue?
    conversation.personal? ? Conversation::LiveDelivery.new(conversation) : new(conversation, turn_started_at: turn_started_at)
  end

  def initialize(conversation, turn_started_at: Time.current)
    @conversation = conversation
    @turn_started_at = turn_started_at
    @sent_text = false
    @lost_text = false
    cadence = adapter.agent_stream_cadence
    @text = Conversation::ChunkBuffer.new(interval: cadence[:interval], max_chars: cadence[:max_chars], whole_markup: cadence[:whole_markup] == true) do |text|
      append(text)
    end
    # A thread has no chart to put where Halon placed one, so it reads the words without the markers.
    @markers = Chat::Chart::Marker::Stream.new { |text| @text.add(text) }
  end

  def output_style = adapter.ai_stream_output_style

  def thinking!
    @answer_id = adapter.start_agent_answer(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      user_id: @conversation.started_by.try(:platform_user_id)
    )[:answer_id]
    @conversation.answer_started!(@answer_id) if @answer_id
  end

  # The answer a lost turn left open, ended where it stopped. Kept on the conversation, since the turn that wrote it is gone.
  def cut_off!
    message_id = @conversation.answer_message_id
    return if message_id.blank?

    adapter.end_interrupted_answer(
      channel_id: @conversation.channel_id, message_id: message_id, shown: @conversation.answer_shown, ending: INTERRUPTED_HERE
    )
  rescue AdapterError => error
    Rails.logger.warn({ event: "conversation.cut_off_undelivered", conversation_id: @conversation.id, error: error.message }.to_json)
  ensure
    @conversation.answer_finished!
  end

  # Text written so far lands before the step card, which shows the tool by name and not its query.
  # A thread shows every step the same way, so what kind it is and how long it took are the dashboard's alone. How a
  # finished step went is said in a word.
  # A step whose coding agent worked through it ends with where it got to.
  def step(key:, step:, status:, kind: nil, seconds: nil, outcome: nil, progress: nil)
    answered = outcome.nil? || outcome.kind == Chat::StepOutcome::KIND_ANSWERED
    cards << step.card if step.card && status == FirefightAi::AgentLoop::STEP_DONE && answered
    # Helpers keep the charts they read under the step that started them.
    charted << key if [ Chat::Tools::CARD_CHART, Chat::Tools::CARD_HELPERS ].include?(step.card&.kind)
    screenshotted << key if step.card&.kind == Chat::Tools::CARD_SCREENSHOTS
    flush_text!
    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: step.shown_line, status: status, outcome: outcome&.kind,
      details: progress&.thread_line
    )
    shown!
    Conversation::Confirming.moved(@conversation, key) if status == FirefightAi::AgentLoop::STEP_DONE
  end

  # A coding agent's work, as the step's one line of details, redrawn in place no more often than the platform allows.
  # The latest thing it did and the counts, never every line.
  def progress(key:, step:, progress:, kind: nil)
    return unless progress_pace.due?(key, progress)

    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: step.shown_line,
      status: FirefightAi::AgentLoop::STEP_RUNNING, details: progress.thread_line
    )
    Conversation::Confirming.moved(@conversation, key, progress: progress)
  end

  # What a long tool says about how far it got is the dashboard's to show. A thread redrawn on every report would be
  # noise, and the step says how it went once it is done.
  def activity(**) = nil

  # Each helper a run_helpers step started, as a line of its own right under that step, redrawn in place as it reads and
  # once it reports, no more often than the platform allows.
  def helpers(key:, helpers:)
    helpers.map { |helper| Chat::Helpers.line(helper) }.each do |line|
      next unless helper_pace.due?(line.key, line)

      adapter.report_agent_step(
        channel_id: @conversation.channel_id, answer_id: @answer_id, key: line.key, title: line.title, status: line.status,
        outcome: line.outcome, details: line.details
      )
    end
  end

  # Making room is the dashboard's to show, so a thread says nothing about it.
  def made_room(_compaction) = nil

  # Said once in the thread, as a finished step, so the people reading know why the answer may read differently.
  def switched_model(switch)
    flush_text!
    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: switch.step_key, title: switch.shown_as,
      status: FirefightAi::AgentLoop::STEP_DONE
    )
    shown!
  end

  def chunk(text)
    @markers.add(text)
  end

  # The answer is already saved in the chat, and the turn has been paid for, so a platform failure
  # is logged rather than retried into a second model call.
  # sources are what Halon read to give the reply (Chat::Sources), one compact line under it.
  def answered!(reply, sources: [])
    flush_text!
    adapter.post_agent_reply(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      answer_id: @answer_id, text: Chat::Chart::Marker.strip(reply), streamed: streamed?, sources: sources
    )
    @conversation.answer_finished!
    mark_answered
    post_cards
  rescue AdapterError => error
    Rails.logger.warn({
      event: "conversation.reply_undelivered", conversation_id: @conversation.id, error: error.message
    }.to_json)
  end

  # Tells the person, or they would watch a spinner forever.
  def failed!(text = FAILED)
    answered!(text)
  end

  # Where it was posted is kept, so it can be redrawn if the person moves past it.
  # The pages Halon's browser saw in this turn go first, so a send is asked about under the page it sends from.
  def confirm!(tool_calls)
    flush_text!
    post_screenshots
    posted = adapter.ask_agent_confirmation(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id, answer_id: @answer_id,
      conversation_id: @conversation.id, confirmations: tool_calls.map { |tool_call| Chat::Tools.confirmation(tool_call) }
    )
    @conversation.confirmation_posted!(posted[:message_id])
    @conversation.answer_finished!
    mark_answered
  rescue AdapterError => error
    Rails.logger.warn({ event: "conversation.confirmation_undelivered", conversation_id: @conversation.id, error: error.message }.to_json)
  end

  # The person asked something else instead of confirming, so the question is redrawn saying it was withdrawn, with
  # no buttons left to press.
  def withdrawn!(tool_calls)
    message_id = @conversation.confirmation_message_id
    return if message_id.blank? || tool_calls.empty?

    asked_together = @conversation.chat.asked_with(tool_calls.first.tool_call_id).map { |tool_call| Chat::Tools.confirmation(tool_call) }
    adapter.update_agent_confirmation(
      channel_id: @conversation.channel_id, message_id: message_id, conversation_id: @conversation.id, confirmations: asked_together
    )
  rescue AdapterError => error
    Rails.logger.warn({ event: "conversation.withdrawal_undelivered", conversation_id: @conversation.id, error: error.message }.to_json)
  end

  private

  def progress_pace = @progress_pace ||= Chat::CodeFixProgress::Pace.new(every: adapter.agent_step_update_interval)

  def helper_pace = @helper_pace ||= Chat::CodeFixProgress::Pace.new(every: adapter.agent_step_update_interval)

  def cards = @cards ||= []

  # The messages this turn answered stop showing that Halon is working on them.
  def mark_answered
    @conversation.take_acknowledged!.each { |message_id| adapter.mark_done(channel_id: @conversation.channel_id, message_id: message_id) }
  end

  def charted = @charted ||= []

  def screenshotted = @screenshotted ||= []

  # Posted under the answer rather than into the stream, so the reply reads first and the table follows it.
  def post_cards
    post_charts
    post_screenshots
    cards.uniq.each do |card|
      next unless card.kind == Chat::Tools::CARD_INTEGRATIONS

      adapter.post_integration_card(
        channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
        card: IntegrationProvider.card_for(@conversation.workspace, IntegrationProvider.category_for!(card.category))
      )
    end
  end

  def post_charts
    return if charted.empty?

    charts = @conversation.chat.charts.drawn_by(charted.uniq, since: @turn_started_at)
    Chat::Chart.posted_under_answer(charts) do |posts|
      adapter.post_charts(channel_id: @conversation.channel_id, thread_id: @conversation.thread_id, charts: posts)
    end
  end

  def post_screenshots
    return if screenshotted.empty?

    screenshots = @conversation.chat.screenshots.where(tool_call_id: screenshotted.uniq)
    screenshotted.clear
    Chat::Screenshot.posted_under_answer(screenshots) do |posts, left_out|
      adapter.post_screenshots(channel_id: @conversation.channel_id, thread_id: @conversation.thread_id, screenshots: posts, left_out: left_out)
    end
  end

  def flush_text!
    @markers.finish
    @text.flush!
  end

  # Streamed text is not repeated, unless a refused piece means the person missed part of it.
  def streamed? = @sent_text && !@lost_text

  def append(text)
    if adapter.append_agent_text(channel_id: @conversation.channel_id, answer_id: @answer_id, text: text)[:streaming]
      @sent_text = true
      shown!
    else
      @lost_text = true
    end
  end

  # Written once, the first time the open answer shows anything.
  def shown!
    return if @shown || @answer_id.nil?

    @shown = true
    @conversation.answer_shown!
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@conversation.workspace)
end
