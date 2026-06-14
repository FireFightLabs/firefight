require "test_helper"

class EntitlementsTest < ActiveSupport::TestCase
  fixtures :workspaces

  teardown { Entitlements.reset_backend! }

  test "open-source default allows every feature" do
    workspace = workspaces(:slack_workspace_one)

    result = Entitlements.check(workspace, Entitlements::AI)

    assert result.allowed?
    assert_not result.blocked?
    assert_nil result.message
    assert Entitlements.allows?(workspace, Entitlements::AI)
  end

  test "a swapped backend is consulted and can deny with a message" do
    workspace = workspaces(:slack_workspace_one)
    Entitlements.backend = Class.new do
      def check(_workspace, _feature)
        Entitlements.deny("Your trial has ended.")
      end
    end.new

    result = Entitlements.check(workspace, Entitlements::AI)

    assert result.blocked?
    assert_equal "Your trial has ended.", result.message
    assert_not Entitlements.allows?(workspace, Entitlements::AI)
  end

  test "reset_backend! restores the open-source default" do
    Entitlements.backend = Class.new do
      def check(_workspace, _feature) = Entitlements.deny("blocked")
    end.new
    assert Entitlements.check(workspaces(:slack_workspace_one), Entitlements::AI).blocked?

    Entitlements.reset_backend!

    assert Entitlements.check(workspaces(:slack_workspace_one), Entitlements::AI).allowed?
  end
end
