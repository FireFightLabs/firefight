# Everything a run says while it works. The platform decides how it looks.
class Investigation::Delivery
  def initialize(investigation)
    @investigation = investigation
  end

  def start!
    return unless channel_id

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

  def stopped!(reason)
    return unless thread_id

    adapter.post_investigation_stopped(
      channel_id: channel_id, thread_id: thread_id, answer_id: @answer_id, reason: reason
    )
  end

  private

  def adapter = @adapter ||= WorkspaceAdapter.for(@investigation.workspace)

  def channel_id = @investigation.channel_id

  def thread_id = @investigation.thread_id

  def started_by = @investigation.triggered_by.try(:display_name)

  def platform_user_id = @investigation.triggered_by.try(:platform_user_id)
end
