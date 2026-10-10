require "test_helper"

class Mcp::Tools::ListNoticesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    disk = Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_DISK, topic: "orders-db volume", summary: "Full around Oct 28.",
                                              severity: Investigation::Notice::SEVERITY_MEDIUM, due_on: Date.new(2026, 10, 28))
    Investigation::Notice.observe!(@workspace, disk).said!(channel_id: "C1", message_id: "1.1")
    Investigation::Notice.observe!(@workspace, disk.with(signal: Investigation::Notice::SIGNAL_COST, topic: "AWS bill", summary: "Up 40%.", due_on: nil))
  end

  test "it lists what Halon raised with when it was said, and why one is still waiting" do
    notices = Mcp::Tools::ListNotices.perform(workspace: @workspace, args: {}).structured_content[:notices]

    disk = notices.find { |notice| notice[:about] == "orders-db volume" }
    assert_equal [ "2026-10-28", 1 ], [ disk[:becomes_a_problem_on], disk[:times_said] ]
    assert notices.find { |notice| notice[:about] == "AWS bill" }.key?(:about)
  end

  test "it narrows by kind and by words" do
    by_signal = Mcp::Tools::ListNotices.perform(workspace: @workspace, args: { signal: Investigation::Notice::SIGNAL_COST }).structured_content[:notices]
    by_words = Mcp::Tools::ListNotices.perform(workspace: @workspace, args: { query: "orders" }).structured_content[:notices]

    assert_equal [ "AWS bill" ], by_signal.map { |notice| notice[:about] }
    assert_equal [ "orders-db volume" ], by_words.map { |notice| notice[:about] }
  end

  test "it reads monitoring, which members hold without a grant" do
    assert_equal [ Ability::Action::RESOURCE_MONITORING, Ability::Action::ACTION_READ ], Mcp::Tools::ListNotices.authorization(@workspace, {})
  end
end
