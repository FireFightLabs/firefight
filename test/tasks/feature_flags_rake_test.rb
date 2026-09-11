require "test_helper"
require "rake"

class FeatureFlagsRakeTest < ActiveSupport::TestCase
  TASKS = %w[feature_flags:enable feature_flags:disable feature_flags:list].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("feature_flags:enable")
    TASKS.each { |task_name| Rake::Task[task_name].reenable }
    @workspace = workspaces(:slack_workspace_one)
  end

  test "enable turns the flag on for the workspace" do
    output, = capture_io do
      Rake::Task["feature_flags:enable"].invoke(FeatureFlags::AI_SRE.to_s, @workspace.id)
    end

    assert FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE)
    assert_match @workspace.name, output
  end

  test "disable turns the flag off for the workspace" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)

    capture_io do
      Rake::Task["feature_flags:disable"].invoke(FeatureFlags::AI_SRE.to_s, @workspace.id)
    end

    assert_not FeatureFlags.enabled?(@workspace, FeatureFlags::AI_SRE)
  end

  test "list names the workspaces each flag is on for" do
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)

    output, = capture_io { Rake::Task["feature_flags:list"].invoke }

    assert_match "#{FeatureFlags::AI_SRE}: #{@workspace.name}", output
  end

  test "list says when a flag is off for every workspace" do
    output, = capture_io { Rake::Task["feature_flags:list"].invoke }

    assert_match "#{FeatureFlags::AI_SRE}: off for every workspace", output
  end

  test "enable stops on a flag that is not declared" do
    _, error = capture_io do
      assert_raises(SystemExit) { Rake::Task["feature_flags:enable"].invoke("not_a_flag", @workspace.id) }
    end

    assert_match "Known flags", error
  end

  test "enable stops on a workspace that does not exist" do
    _, error = capture_io do
      assert_raises(SystemExit) do
        Rake::Task["feature_flags:enable"].invoke(FeatureFlags::AI_SRE.to_s, SecureRandom.uuid)
      end
    end

    assert_match "No workspace", error
  end
end
