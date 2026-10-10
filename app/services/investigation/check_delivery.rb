# What a scheduled check says, which is only news: each problem it noted that is new, worse or back after a long time,
# in the channel of the team that owns it (Investigation::Notice.channel_for). Nobody asked for the run, so its steps
# are said nowhere and it never announces itself. A problem noted before the run stopped is still said.
class Investigation::CheckDelivery
  def initialize(investigation)
    @investigation = investigation
  end

  def start! = nil

  def step(**) = nil

  def answered!(_finding) = say_news

  def stopped!(_reason, **) = say_news

  private

  def say_news
    @investigation.workspace.investigation_notices.unsaid.where(investigation: @investigation).includes(:resource, :check).find_each do |notice|
      say(notice)
    end
  end

  def say(notice)
    return unless notice.claim!

    channel_id = notice.channel
    return notice.unsaid_because!(Investigation::Notice::NO_CHANNEL) unless channel_id

    posted = adapter.post_monitoring_notice(channel_id: channel_id, notice: notice)
    notice.said!(channel_id: posted[:channel_id].presence || channel_id, message_id: posted[:message_id])
  rescue AdapterError => error
    Rails.logger.warn({ event: "monitoring.notice_undelivered", notice_id: notice.id, error: error.class.name }.to_json)
    notice.unsaid_because!(Investigation::Notice::NOT_DELIVERED)
  end

  def adapter = @adapter ||= WorkspaceAdapter.for(@investigation.workspace)
end
