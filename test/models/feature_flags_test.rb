require "test_helper"

class FeatureFlagsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @other_workspace = workspaces(:slack_workspace_two)
  end

  test "a flag is off for every workspace by default" do
    assert_not FeatureFlags.enabled?(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
  end

  test "enabling a flag turns it on for that workspace only" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)

    assert FeatureFlags.enabled?(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
    assert_not FeatureFlags.enabled?(@other_workspace, FeatureFlags::CHATGPT_SIGN_IN)
  end

  test "disabling a flag turns it off again" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
    FeatureFlags.disable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)

    assert_not FeatureFlags.enabled?(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
  end

  test "accepts a flag name given as a string, as rake passes it" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN.to_s)

    assert FeatureFlags.enabled?(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
  end

  test "lists the workspaces a flag is on for" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)

    assert_equal [ @workspace ], FeatureFlags.workspaces_with(FeatureFlags::CHATGPT_SIGN_IN).to_a
  end

  test "rejects a flag that is not declared" do
    assert_raises(FeatureFlags::UnknownFlag) { FeatureFlags.enabled?(@workspace, :not_a_flag) }
    assert_raises(FeatureFlags::UnknownFlag) { FeatureFlags.enable!(@workspace, :not_a_flag) }
  end

  test "a global flag is off until turned on for everyone" do
    assert_not FeatureFlags.enabled_globally?(FeatureFlags::SELF_SERVE_SIGNUP)

    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    assert FeatureFlags.enabled_globally?(FeatureFlags::SELF_SERVE_SIGNUP)

    FeatureFlags.disable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)
    assert_not FeatureFlags.enabled_globally?(FeatureFlags::SELF_SERVE_SIGNUP)
  end

  test "a global flag is never set per workspace, and a workspace flag never globally" do
    assert_raises(FeatureFlags::UnknownFlag) { FeatureFlags.enable!(@workspace, FeatureFlags::SELF_SERVE_SIGNUP) }
    assert_raises(FeatureFlags::UnknownFlag) { FeatureFlags.enable_globally!(FeatureFlags::CHATGPT_SIGN_IN) }
  end
end
