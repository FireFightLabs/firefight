require "test_helper"
require "rake"

class FeatureFlagsRakeTest < ActiveSupport::TestCase
  TASKS = %w[feature_flags:enable feature_flags:disable feature_flags:enable_globally feature_flags:disable_globally feature_flags:list].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("feature_flags:enable")
    TASKS.each { |task_name| Rake::Task[task_name].reenable }
    @workspace = workspaces(:slack_workspace_one)
  end

  test "enable turns the flag on for the workspace" do
    output, = capture_io do
      Rake::Task["feature_flags:enable"].invoke(FeatureFlags::CHATGPT_SIGN_IN.to_s, @workspace.id)
    end

    assert FeatureFlags.enabled?(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
    assert_match @workspace.name, output
  end

  test "disable turns the flag off for the workspace" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)

    capture_io do
      Rake::Task["feature_flags:disable"].invoke(FeatureFlags::CHATGPT_SIGN_IN.to_s, @workspace.id)
    end

    assert_not FeatureFlags.enabled?(@workspace, FeatureFlags::CHATGPT_SIGN_IN)
  end

  test "list names the workspaces each flag is on for" do
    FeatureFlags.enable!(@workspace, FeatureFlags::CHATGPT_SIGN_IN)

    output, = capture_io { Rake::Task["feature_flags:list"].invoke }

    assert_match "#{FeatureFlags::CHATGPT_SIGN_IN}: #{@workspace.name}", output
  end

  test "list says when a flag is off for every workspace" do
    output, = capture_io { Rake::Task["feature_flags:list"].invoke }

    assert_match "#{FeatureFlags::CHATGPT_SIGN_IN}: off for every workspace", output
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
        Rake::Task["feature_flags:enable"].invoke(FeatureFlags::CHATGPT_SIGN_IN.to_s, SecureRandom.uuid)
      end
    end

    assert_match "No workspace", error
  end

  test "enable_globally and disable_globally turn a global flag on and off for everyone" do
    output, = capture_io { Rake::Task["feature_flags:enable_globally"].invoke(FeatureFlags::SELF_SERVE_SIGNUP.to_s) }
    assert FeatureFlags.enabled_globally?(FeatureFlags::SELF_SERVE_SIGNUP)
    assert_match "on for everyone", output

    capture_io { Rake::Task["feature_flags:disable_globally"].invoke(FeatureFlags::SELF_SERVE_SIGNUP.to_s) }
    assert_not FeatureFlags.enabled_globally?(FeatureFlags::SELF_SERVE_SIGNUP)
  end

  test "list says whether each global flag is on" do
    FeatureFlags.enable_globally!(FeatureFlags::SELF_SERVE_SIGNUP)

    output, = capture_io { Rake::Task["feature_flags:list"].invoke }

    assert_match "#{FeatureFlags::SELF_SERVE_SIGNUP}: on for everyone", output
  end

  test "enable_globally stops on a flag that is set per workspace" do
    _, error = capture_io do
      assert_raises(SystemExit) { Rake::Task["feature_flags:enable_globally"].invoke(FeatureFlags::CHATGPT_SIGN_IN.to_s) }
    end

    assert_match "set per workspace", error
  end
end
