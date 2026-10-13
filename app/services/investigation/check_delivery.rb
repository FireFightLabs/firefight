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

  def say(notice) = Investigation::NoticeDelivery.new(@investigation.workspace).say!(notice)
end
