require "test_helper"

class FirefightAi::MemoryCheckerTest < ActiveSupport::TestCase
  test "the memory check's prompt says how to settle each memory and how to finish, and carries no workspace of its own" do
    workspace = workspaces(:slack_workspace_one)
    checker = FirefightAi::MemoryChecker.new(workspace, inferable: incidents(:active_critical_ws1))

    context = checker.send(:inference_context)

    assert_equal FirefightAi::MemoryChecker::FEATURE, context[:prompt_template]
    assert_equal FirefightAi::Prompt.version(context[:prompt_text]), context[:prompt_version]
    assert_includes context[:prompt_text], FirefightAi::MemoryChecker::SETTLE_TOOL
    assert_includes context[:prompt_text], FirefightAi::MemoryChecker::FINISH_TOOL
    assert_includes context[:prompt_text], "Unsure is a good answer"
    assert_no_match(/#{workspace.name}/, context[:prompt_text])
  end

  test "the opening explains tonight's memories where it meets them" do
    opening = FirefightAi::MemoryChecker.new(workspaces(:slack_workspace_one), inferable: nil)
                                        .send(:opening, { "memories_to_check" => [ { "id" => "m1", "fact" => "web deploys from main" } ] })

    assert_includes opening, "memories_to_check are tonight's memories"
    assert_includes opening, "web deploys from main"
  end
end
