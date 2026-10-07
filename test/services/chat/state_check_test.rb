require "test_helper"

# Halon reads how things stand now for an approved call before a person runs it, only through reads, as that person.
class Chat::StateCheckTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    faylee = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "cloudflare", name: "Faylee", slug: "faylee",
                                             settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
    faylee.integration_environments.create!
    @write = faylee.tools.create!(name: "execute", description: "Call the API", params_schema: {}, enabled: true, read_only: false)
    purge = faylee.tools.create!(name: "purge_cache", description: "Purge the cache", params_schema: {}, enabled: true, read_only: false)
    Ability::Grant.create!(workspace: @workspace, principal: @bob, action: purge.ability_action)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @bob)
    approval = @workspace.ability_approvals.create!(principal: @bob, principal_label: "user:Bob Jones", action_key: @write.action_key,
                                                    request_digest: "d", required_role: "admin")
    @held = Chat::HeldCall.create!(chat: conversation.chat_record, approval: approval, tool_name: "faylee_execute")
    @call = Chat::StateCheck::Call.new(named: "Execute on Faylee (Cloudflare)", asked: [ [ "code", "scale web to 0" ] ], approved_by: "Alice Smith")
    Investigation.stubs(:unavailable_reason).returns(nil)
  end

  test "it reads on a chat of its own, as the person, never offered a change, and ends with what it reported" do
    FirefightAi::StateChecker.any_instance.expects(:run).with do |chat:, tools:, answered:, **|
      assert_equal @held, chat.owner
      assert_match "Execute on Faylee (Cloudflare)", chat.messages.last.content
      assert_not answered.call
      tools.find { |tool| tool.name == Chat::StateCheck::Report::NAME }.execute(now: "web already runs 0 instances.", change: "already_done")
      answered.call
    end

    report = check

    assert_equal [ "web already runs 0 instances.", Chat::CurrentState::DONE_ALREADY ], [ report.state, report.change ]
    reads = Chat::Tools.catalog(Chat::StateCheck.new(owner: @held, workspace: @workspace, principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION))
    assert_equal Chat::Tools::STATE_READS_ONLY, reads.find { |entry| entry.name == "faylee_purge_cache" }.state
  end

  test "a check that cannot run or never reports says nobody checked, rather than leaving the card waiting" do
    FirefightAi::StateChecker.any_instance.stubs(:run).raises(FirefightAi::TransientError, "provider down")
    assert_equal Chat::CurrentState::UNKNOWN, check.change

    Investigation.stubs(:unavailable_reason).returns("Investigations are not turned on for this workspace.")
    report = check
    assert_equal [ Chat::CurrentState::UNKNOWN, "Investigations are not turned on for this workspace." ], [ report.change, report.state ]
  end

  private

  def check
    Chat::StateCheck.run(owner: @held, workspace: @workspace, principal: @bob, source: AbilityGateway::SOURCE_CONVERSATION, call: @call)
  end
end
