# Everything a run says while it works. The platform decides how it looks. A run on an incident speaks in the
# incident's channel, a question asked in a channel is answered there, and a question from a dashboard chat is
# answered by that chat's card, which is told to look again whenever the run moves.
class Investigation::Delivery
  def initialize(investigation)
    @investigation = investigation
  end

  # A resumed run already said it started, and picks its thread back up rather than opening a second.
  def start!
    @investigation.note_started!
    tell_chat
    return unless channel_id
    return if thread_id

    started = adapter.post_investigation_started(
      channel_id: channel_id, incident: @investigation.incident, question: @investigation.question, started_by: started_by,
      fallback_user_id: (platform_user_id unless @investigation.incident)
    )
    # A question may have been answered somewhere else than asked, directly to whoever asked.
    answered_in = started[:channel_id].presence || channel_id
    @investigation.update!(thread_id: started[:message_id], channel_id: (answered_in unless @investigation.incident))
    @answer_id = adapter.start_agent_answer(
      channel_id: channel_id, thread_id: started[:message_id], user_id: platform_user_id
    )[:answer_id]
  end

  def step(key:, title:, status:)
    tell_chat
    return unless thread_id

    adapter.report_agent_step(
      channel_id: channel_id, answer_id: @answer_id, key: key, title: title, status: status
    )
  end

  def answered!(finding)
    @investigation.note_answered!(finding)
    tell_chat
    return unless thread_id

    adapter.post_investigation_answer(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, finding: finding
    )
    posted!
    post_charts
  end

  # rerunnable is for a stop on our side. A spent budget or a person's stop would only end the same way.
  def stopped!(reason, rerunnable: false)
    @investigation.note_stopped!(reason)
    tell_chat
    return unless thread_id

    adapter.post_investigation_stopped(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, reason: reason,
      rerun: (@investigation.incident if rerunnable),
      rerun_question: (@investigation if rerunnable && @investigation.incident.nil?), investigation: @investigation
    )
    posted!
    post_charts
  end

  private

  # Only after the platform took it, so a run whose last post failed is one an operator can find.
  def posted!
    @investigation.update_columns(answer_posted_at: Time.current)
  end

  # The charts the run drew, under its answer or its reason for stopping. The answer is already posted, so a chart that
  # cannot be posted is logged rather than failing the run.
  def post_charts
    charts = @investigation.chat&.charts
    return if charts.blank?

    Chat::Chart.posted_under_answer(charts) do |posts|
      adapter.post_charts(channel_id: channel_id, thread_id: thread_id, charts: posts)
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "investigation.charts_undelivered", investigation_id: @investigation.id, error: error.message }.to_json)
  end

  def tell_chat
    conversation = @investigation.conversation
    return unless conversation

    ConversationChannel.broadcast_to(conversation, type: Conversation::LiveDelivery::EVENT_INVESTIGATION, investigation_id: @investigation.id)
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@investigation.workspace)

  def channel_id = @investigation.channel_id

  def thread_id = @investigation.thread_id

  def started_by = @investigation.triggered_by.try(:display_name)

  def platform_user_id = @investigation.triggered_by.try(:platform_user_id)
end
