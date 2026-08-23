require "test_helper"

class Workspace::SuspensionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "not suspended by default" do
    assert_not @workspace.suspended?
  end

  test "suspending requires a reason" do
    @workspace.suspended_at = Time.current

    assert_not @workspace.valid?
    assert_includes @workspace.errors[:suspended_reason], "can't be blank"
  end

  test "rejects a reason outside the known set" do
    @workspace.assign_attributes(suspended_at: Time.current, suspended_reason: "because")

    assert_not @workspace.valid?
  end

  test "each reason carries its own message" do
    @workspace.update!(suspended_at: Time.current, suspended_reason: Workspace::Suspension::SUSPENSION_PAYMENT_FAILED)
    assert_match(/payment issue/, @workspace.suspension_message)

    @workspace.update!(suspended_reason: Workspace::Suspension::SUSPENSION_MISUSE)
    assert_match(/misuse/, @workspace.suspension_message)
  end
end
