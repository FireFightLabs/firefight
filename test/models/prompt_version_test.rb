require "test_helper"

class PromptVersionTest < ActiveSupport::TestCase
  test "a wording is written down once, however many calls use it" do
    PromptVersion.seen.clear
    version = FirefightAi::Prompt.version("Be brief.")

    3.times { PromptVersion.remember!(template: "conversation", version: version, text: "Be brief.") }

    assert_equal 1, PromptVersion.where(template: "conversation", version: version).count
  end

  test "an edited prompt gets its own version, and the old wording stays readable" do
    PromptVersion.seen.clear
    was = FirefightAi::Prompt.version("Be brief.")
    now = FirefightAi::Prompt.version("Be brief and exact.")
    PromptVersion.remember!(template: "conversation", version: was, text: "Be brief.")
    PromptVersion.remember!(template: "conversation", version: now, text: "Be brief and exact.")

    assert_not_equal was, now
    assert_equal "Be brief.", PromptVersion.find_by(version: was).text
  end

  test "every prompt the agent runs on says which wording produced a call" do
    workspace = workspaces(:slack_workspace_one)
    responder = FirefightAi::Responder.new(workspace, inferable: incidents(:active_critical_ws1))

    context = responder.send(:inference_context)

    assert_equal "conversation", context[:prompt_template]
    assert_equal FirefightAi::Prompt.version(context[:prompt_text]), context[:prompt_version]
    assert_no_match(/acting for/, context[:prompt_text])
  end

  # The incident arrives in the opening message, so the versioned wording never names one.
  test "the investigator's prompt carries no incident of its own either" do
    workspace = workspaces(:slack_workspace_one)
    incident = incidents(:active_critical_ws1)
    investigator = FirefightAi::Investigator.new(workspace, inferable: incident)

    context = investigator.send(:inference_context)

    assert_equal FirefightAi::Investigator::FEATURE, context[:prompt_template]
    assert_equal FirefightAi::Prompt.version(context[:prompt_text]), context[:prompt_version]
    assert_no_match(/#{incident.identifier}|#{incident.name}|acting for/, context[:prompt_text])
  end
end
