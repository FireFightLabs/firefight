require "test_helper"

class FeatureFlagsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @other_workspace = workspaces(:slack_workspace_two)
  end

  test "a flag is off for every workspace by default" do
    assert_not FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE)
  end

  test "enabling a flag turns it on for that workspace only" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)

    assert FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE)
    assert_not FeatureFlags.enabled?(@other_workspace, FeatureFlags::AI_SRE)
  end

  test "disabling a flag turns it off again" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    FeatureFlags.disable!(@workspace, FeatureFlags::AI_SRE)

    assert_not FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE)
  end

  test "accepts a flag name given as a string, as rake passes it" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE.to_s)

    assert FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE)
  end

  test "lists the workspaces a flag is on for" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)

    assert_equal [ @workspace ], FeatureFlags.workspaces_with(FeatureFlags::AI_SRE).to_a
  end

  test "rejects a flag that is not declared" do
    assert_raises(FeatureFlags::UnknownFlag) { FeatureFlags.enabled?(@workspace, :not_a_flag) }
    assert_raises(FeatureFlags::UnknownFlag) { FeatureFlags.enable!(@workspace, :not_a_flag) }
  end
end
