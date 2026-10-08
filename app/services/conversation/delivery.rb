# What the agent says while it is answering someone. The platform decides how it looks.
class Conversation::Delivery
  FAILED = "Something went wrong on my side, so I did not finish that one. Ask me again.".freeze

  # Saved in the chat and said where the person asked, so a turn that could not finish is never a silence.
  def self.give_up!(conversation, text)
    conversation.note!(text)
    conversation.reply_delivered!
    self.for(conversation).failed!(text)
  end

  def self.for(conversation)
    return Conversation::QuietDelivery.new(conversation) if conversation.mcp?
    conversation.personal? ? Conversation::LiveDelivery.new(conversation) : new(conversation)
  end

  def initialize(conversation)
    @conversation = conversation
    @sent_text = false
    @lost_text = false
    cadence = adapter.agent_stream_cadence
    @text = Conversation::ChunkBuffer.new(interval: cadence[:interval], max_chars: cadence[:max_chars]) do |text|
      append(text)
    end
  end

  def output_style = adapter.ai_stream_output_style

  def thinking!
    @answer_id = adapter.start_agent_answer(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      user_id: @conversation.started_by.try(:platform_user_id)
    )[:answer_id]
  end

  # Text written so far lands before the step card, which shows the tool by name and not its query.
  # A thread shows every step the same way, so what kind it is and how long it took are the dashboard's alone. How a
  # finished step went is said in a word.
  # A step whose coding agent worked through it ends with where it got to.
  def step(key:, step:, status:, kind: nil, seconds: nil, outcome: nil, progress: nil)
    answered = outcome.nil? || outcome.kind == Chat::StepOutcome::KIND_ANSWERED
    cards << step.card if step.card && status == FirefightAi::AgentLoop::STEP_DONE && answered
    charted << key if step.card&.kind == Chat::Tools::CARD_CHART
    @text.flush!
    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: step.title, status: status, outcome: outcome&.kind,
      details: progress&.headline
    )
  end

  # A coding agent's work, as the step's one line of details, redrawn in place no more often than the platform allows.
  # The latest thing it did and the counts, never every line.
  def progress(key:, step:, progress:, kind: nil)
    return unless progress_pace.due?(key, progress)

    adapter.report_agent_step(
      channel_id: @conversation.channel_id, answer_id: @answer_id, key: key, title: step.title,
      status: FirefightAi::AgentLoop::STEP_RUNNING, details: progress.headline
    )
  end

  # Making room is the dashboard's to show, so a thread says nothing about it.
  def made_room(_compaction) = nil

  def chunk(text)
    @text.add(text)
  end

  # The answer is already saved in the chat, and the turn has been paid for, so a platform failure
  # is logged rather than retried into a second model call.
  def answered!(reply)
    @text.flush!
    adapter.post_agent_reply(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id,
      answer_id: @answer_id, text: reply, streamed: streamed?
    )
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
  def confirm!(tool_calls)
    @text.flush!
    posted = adapter.ask_agent_confirmation(
      channel_id: @conversation.channel_id, thread_id: @conversation.thread_id, answer_id: @answer_id,
      conversation_id: @conversation.id, confirmations: tool_calls.map { |tool_call| Chat::Tools.confirmation(tool_call) }
    )
    @conversation.confirmation_posted!(posted[:message_id])
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

  def cards = @cards ||= []

  def charted = @charted ||= []

  # Posted under the answer rather than into the stream, so the reply reads first and the table follows it.
  def post_cards
    post_charts
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

    charts = @conversation.chat.charts.where(tool_call_id: charted.uniq)
    Chat::Chart.posted_under_answer(charts) do |posts|
      adapter.post_charts(channel_id: @conversation.channel_id, thread_id: @conversation.thread_id, charts: posts)
    end
  end

  # Streamed text is not repeated, unless a refused piece means the person missed part of it.
  def streamed? = @sent_text && !@lost_text

  def append(text)
    if adapter.append_agent_text(channel_id: @conversation.channel_id, answer_id: @answer_id, text: text)[:streaming]
      @sent_text = true
    else
      @lost_text = true
    end
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@conversation.workspace)
end
