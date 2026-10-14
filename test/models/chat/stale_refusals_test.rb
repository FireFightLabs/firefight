require "test_helper"

# A result that said something could not be used, or a connected system's error, describes the moment it was read. Seen
# in a real chat, Halon told the person a repository needed a paid plan six hours after the one call that said so, two
# turns on, though the cause had since been fixed. The next message reaches Halon with what those results said and how
# long ago, so it checks again rather than restating them as how things stand.
class Chat::StaleRefusalsTest < ActiveSupport::TestCase
  PLAN = "github.fix_code failed: GitHub: Upgrade to GitHub Pro or make this repository public to enable this feature.".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: workspace_memberships(:alice_workspace_one))
    @chat = @conversation.chat_record
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.tools.create!(name: "fix_code", description: "Fix code", read_only: false, enabled: true, params_schema: { "type" => "object" })
  end

  test "a connected system's error from a few turns back is named with how long ago it was read, and Firefight's own refusals are not" do
    travel_to(6.hours.ago) do
      asked!("address the review")
      failed!("github_fix_code", "<tool_result tool=\"github_fix_code\" trust=\"untrusted\">\n#{PLAN}\n</tool_result>")
      failed!("update_plan", "Not updated. Step 2 already ended as done.")
    end
    travel_to(5.hours.ago) { asked!("why didn't you make the changes?") }
    asked!("make the changes now")

    note = Chat::StaleRefusals.note(@chat)

    assert_includes note, "- github_fix_code, read 6 hours ago: #{PLAN}"
    assert_not_includes note, "update_plan"
    assert_includes note, "Never repeat one as how things stand now"
  end

  test "an error more turns back than the note looks is left out" do
    travel_to(6.hours.ago) do
      asked!("address the review")
      failed!("github_fix_code", PLAN)
    end
    (Chat::StaleRefusals::TURNS_BACK + 1).times { |index| travel_to((5 - index).hours.ago) { asked!("and now?") } }

    assert_nil Chat::StaleRefusals.note(@chat)
  end

  private

  def asked!(words) = @chat.messages.create!(role: Chat::Message::ROLE_USER, content: words)

  def failed!(name, answer)
    message = @chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
    call = message.ruby_llm_tool_calls.create!(tool_call_id: "call_#{SecureRandom.hex(3)}", name: name, arguments: {})
    call.update!(result: @chat.messages.create!(role: Chat::Message::ROLE_TOOL, content: answer), failed: true, failure_kind: Chat::StepOutcome::FAILURE_ERROR)
  end
end
