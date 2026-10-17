# Everything a run says while it works. The platform decides how it looks. A run on an incident speaks in the
# incident's channel, a question asked in a channel is answered there, and a question from a dashboard chat is
# answered by that chat's card, which is told to look again whenever the run moves.
# The message that opens the run's thread is its checklist (Investigation::Progress), redrawn in place as the run moves
# and no more often than the platform allows, so the channel follows along without a word posted. The run works in the
# thread, and only its answer is also posted where the whole channel sees it.
class Investigation::Delivery
  def initialize(investigation)
    @investigation = investigation
    @progress_lock = Mutex.new
  end

  # A rehearsal says nothing, and a scheduled check says only the problems it found that are news.
  def self.for(investigation)
    return Investigation::QuietDelivery.new(investigation) if investigation.rehearsal?
    return Investigation::CheckDelivery.new(investigation) if investigation.scheduled?

    new(investigation)
  end

  # A resumed run already said it started, and picks its thread back up rather than opening a second.
  def start!
    @investigation.note_started!
    tell_chat
    return unless channel_id
    return if thread_id

    progress = Investigation::Progress.new(@investigation)
    started = adapter.post_investigation_started(
      channel_id: channel_id, incident: @investigation.incident, question: shown_question, started_by: started_by,
      fallback_user_id: (platform_user_id unless @investigation.incident), progress: progress
    )
    @shown_progress = progress.signature
    # A question may have been answered somewhere else than asked, directly to whoever asked.
    answered_in = started[:channel_id].presence || channel_id
    @investigation.update!(thread_id: started[:message_id], channel_id: (answered_in unless @investigation.incident))
    @answer_id = adapter.start_agent_answer(
      channel_id: channel_id, thread_id: started[:message_id], user_id: platform_user_id
    )[:answer_id]
  end

  def step(key:, title:, status:, outcome: nil)
    tell_chat
    return unless thread_id

    adapter.report_agent_step(
      channel_id: channel_id, answer_id: @answer_id, key: key, title: title, status: status, outcome: outcome&.kind
    )
    show_progress
  end

  # Each helper a run_helpers step started, as a line of its own right under that step, redrawn in place as it reads and
  # once it reports, no more often than the platform allows. The run's page reads them on its next look.
  def helpers(key:, helpers:)
    return unless thread_id

    helpers.map { |helper| Chat::Helpers.line(helper) }.each do |line|
      next unless helper_pace.due?(line.key, line)

      adapter.report_agent_step(
        channel_id: channel_id, answer_id: @answer_id, key: line.key, title: line.title, status: line.status,
        outcome: line.outcome, details: line.details
      )
    end
    show_progress
  end

  def answered!(finding)
    @investigation.note_answered!(finding)
    tell_chat
    return unless thread_id

    show_progress(Investigation::Progress.new(@investigation))
    answer = adapter.post_investigation_answer(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, finding: finding
    )
    posted!(answer.to_h[:message_id])
    post_charts
    post_screenshots
  end

  # rerunnable is for a stop on our side. A spent budget or a person's stop would only end the same way.
  # where_it_stopped is what the run did before it could not carry on, so responders pick up from there without it.
  def stopped!(reason, rerunnable: false, where_it_stopped: nil)
    @investigation.note_stopped!(reason)
    tell_chat
    return unless thread_id

    show_progress(Investigation::Progress.new(@investigation, stop_reason: reason))
    adapter.post_investigation_stopped(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, reason: reason, where_it_stopped: where_it_stopped,
      rerun: (@investigation.incident if rerunnable),
      rerun_question: (@investigation if rerunnable && @investigation.incident.nil?), investigation: @investigation
    )
    posted!
    post_charts
    post_screenshots
  end

  private

  # The checklist redrawn when it says something new. While the run works that is at most once an interval, and the
  # last word, a finished checklist, always goes. A redraw the platform refuses is logged, since the run goes on.
  def show_progress(progress = nil)
    @progress_lock.synchronize do
      now = Time.current.to_f
      return if progress.nil? && @progress_shown_at && now - @progress_shown_at < adapter.agent_step_update_interval

      progress ||= Investigation::Progress.new(@investigation)
      return if progress.signature == @shown_progress

      adapter.update_investigation_progress(
        channel_id: channel_id, message_id: thread_id, incident: @investigation.incident, question: shown_question, started_by: started_by,
        progress: progress
      )
      # Noted only once the platform took it, so a refused redraw, the last one too, is tried again.
      @progress_shown_at = now
      @shown_progress = progress.signature
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "investigation.progress_not_shown", investigation_id: @investigation.id, error: error.message }.to_json)
  end

  # Only after the platform took it, so a run whose last post failed is one an operator can find.
  def posted!(message_id = nil)
    @investigation.update_columns({ answer_posted_at: Time.current, answer_message_id: message_id }.compact)
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

  # The pages the run's browser saw while it worked, under its answer like its charts. A fix's page check is drawn on the run
  # page under its step, and the fix's own message says how it went.
  def post_screenshots
    screenshots = @investigation.chat&.screenshots&.where(remediation_step_id: nil)
    return if screenshots.blank?

    Chat::Screenshot.posted_under_answer(screenshots) do |posts, left_out|
      adapter.post_screenshots(channel_id: channel_id, thread_id: thread_id, screenshots: posts, left_out: left_out)
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "investigation.screenshots_undelivered", investigation_id: @investigation.id, error: error.message }.to_json)
  end

  def tell_chat
    conversation = @investigation.conversation
    return unless conversation

    ConversationChannel.broadcast_to(conversation, type: Conversation::LiveDelivery::EVENT_INVESTIGATION, investigation_id: @investigation.id)
  end

  def helper_pace = @helper_pace ||= Chat::CodeFixProgress::Pace.new(every: adapter.agent_step_update_interval)

  def adapter = @adapter ||= WorkspaceAdapter.for(@investigation.workspace)

  def channel_id = @investigation.channel_id

  def thread_id = @investigation.thread_id

  def started_by = @investigation.started_by_alert? ? "the alert that opened this incident" : @investigation.triggered_by.try(:actor_display_name)

  def platform_user_id = @investigation.triggered_by.try(:platform_user_id)

  # Posted back as the platform shows it, so a mention or a broadcast in it never notifies anyone again.
  def shown_question
    return @shown_question if defined?(@shown_question)

    @shown_question = platform_question
  end

  def platform_question
    question = @investigation.question
    return question unless question.present? && @investigation.question_in_platform_markup?

    adapter.messages_as_text(texts: [ question ])[question]
  end
end
