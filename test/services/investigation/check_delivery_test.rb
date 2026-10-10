require "test_helper"

class Investigation::CheckDeliveryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @workspace.update!(halon_monitoring_channel: "C_MONITORING")
    @check = @workspace.investigation_checks.create!(name: "Disks", kind: Investigation::Check::KIND_DISK, cadence: Investigation::Check::CADENCE_DAILY,
                                                     hour: 9, time_zone: "UTC")
    @run = @workspace.investigations.create!(subject: @check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400)
  end

  def note(topic, severity: Investigation::Notice::SEVERITY_MEDIUM)
    reading = Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: topic, summary: "#{topic} fills by Oct 28.",
                                                 severity: severity, due_on: Date.new(2026, 10, 28))
    Investigation::Notice.observe!(@workspace, reading, check: @check, investigation: @run)
  end

  test "a finished check says each new problem once, in the monitoring channel, and never announces itself" do
    note("orders-db volume")
    Slack::Client.expects(:post_message).once.with do |arguments|
      arguments[:channel] == "C_MONITORING" && arguments[:text].include?("Disk space: orders-db volume")
    end.returns({ ok: true, ts: "1.1", channel: "C_MONITORING" })

    delivery = Investigation::CheckDelivery.new(@run)
    delivery.start!
    delivery.answered!(nil)

    notice = @workspace.investigation_notices.sole
    assert_not notice.unsaid
    assert_equal 1, notice.times_said
    assert_equal "1.1", notice.message_id
  end

  test "a problem noted before a run stopped is still said" do
    note("orders-db volume")
    stub_post_message

    Investigation::CheckDelivery.new(@run).stopped!("Budget spent before it could answer")

    assert_equal 1, @workspace.investigation_notices.sole.times_said
  end

  test "with nowhere to say it, it waits with why, and is said by a later run" do
    @workspace.update!(halon_monitoring_channel: nil)
    note("orders-db volume")
    Slack::Client.expects(:post_message).never

    Investigation::CheckDelivery.new(@run).answered!(nil)

    notice = @workspace.investigation_notices.sole
    assert notice.unsaid
    assert_equal Investigation::Notice::NO_CHANNEL, notice.unsaid_reason
  end

  test "a channel Firefight cannot post in leaves it unsaid with why" do
    note("orders-db volume")
    stub_post_message(raises: AdapterError::NotInChannel.new("not_in_channel"))

    Investigation::CheckDelivery.new(@run).answered!(nil)

    assert_equal Investigation::Notice::NOT_DELIVERED, @workspace.investigation_notices.sole.unsaid_reason
  end
end
