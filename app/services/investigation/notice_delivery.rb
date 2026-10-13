# Says a notice once, in the channel given or the one its resource's team owns, through the platform. A notice whose
# post failed, or that has nowhere to go, stays unsaid with why, so the next run says it.
class Investigation::NoticeDelivery
  def initialize(workspace)
    @workspace = workspace
  end

  # Answers whether it was said now.
  def say!(notice, channel_id: notice.channel)
    return false unless notice.claim!

    unless channel_id
      notice.unsaid_because!(Investigation::Notice::NO_CHANNEL)
      return false
    end

    posted = adapter.post_monitoring_notice(channel_id: channel_id, notice: notice)
    notice.said!(channel_id: posted[:channel_id].presence || channel_id, message_id: posted[:message_id])
    true
  rescue AdapterError => error
    Rails.logger.warn({ event: "monitoring.notice_undelivered", notice_id: notice.id, error: error.class.name }.to_json)
    notice.unsaid_because!(Investigation::Notice::NOT_DELIVERED)
    false
  end

  private

  def adapter = @adapter ||= WorkspaceAdapter.for(@workspace)
end
