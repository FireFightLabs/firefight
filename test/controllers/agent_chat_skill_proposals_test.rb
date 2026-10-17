require "test_helper"

# A skill Halon proposed in a chat shows there while the workspace keeps its own skills, and not once it no longer does,
# since accepting or dismissing it is then a page that does not exist.
class AgentChatSkillProposalsTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    Entitlements.stubs(:allows?).returns(true)
    @conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    @conversation.chat_record
    @proposal = Chat::CustomSkill.propose_for!(@workspace, name: "rotate_keys", reason: "Asked twice this week.", conversation: @conversation,
                                               content: { "when" => "Someone asks to rotate keys", "tools" => [], "steps" => "1. Rotate them." })
    sign_in(users(:bob), @workspace)
  end

  def thread_headers = inertia_partial_headers("agent/index", AgentChatsController::THREAD_PROPS)

  test "the chat shows the proposal while the workspace keeps its own skills" do
    get agent_chat_path(@conversation), headers: thread_headers

    assert_equal [ @proposal.id ], inertia_props[AgentChatsController::PROP_SKILL_PROPOSALS].pluck("id")
  end
end
