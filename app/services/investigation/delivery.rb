# Everything a run says while it works. The platform decides how it looks.
class Investigation::Delivery
  def initialize(investigation)
    @investigation = investigation
  end

  # A resumed run already said it started, and picks its thread back up rather than opening a second.
  def start!
    return unless channel_id
    return if thread_id

    started = adapter.post_investigation_started(
      channel_id: channel_id, incident: @investigation.subject, started_by: started_by
    )
    @investigation.update!(thread_id: started[:message_id])
    @answer_id = adapter.start_agent_answer(
      channel_id: channel_id, thread_id: started[:message_id], user_id: platform_user_id
    )[:answer_id]
  end

  def step(key:, title:, status:)
    return unless thread_id

    adapter.report_agent_step(
      channel_id: channel_id, answer_id: @answer_id, key: key, title: title, status: status
    )
  end

  def answered!(finding)
    return unless thread_id

    adapter.post_investigation_answer(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, finding: finding
    )
  end

  # rerunnable is for a stop on our side. A spent budget or a person's stop would only end the same way.
  def stopped!(reason, rerunnable: false)
    return unless thread_id

    adapter.post_investigation_stopped(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, reason: reason,
      rerun: (@investigation.incident if rerunnable)
    )
  end

  private

  def adapter = @adapter ||= WorkspaceAdapter.for(@investigation.workspace)

  def channel_id = @investigation.channel_id

  def thread_id = @investigation.thread_id

  def started_by = @investigation.triggered_by.try(:display_name)

  def platform_user_id = @investigation.triggered_by.try(:platform_user_id)
end
