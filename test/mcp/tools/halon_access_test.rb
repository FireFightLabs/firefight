require "test_helper"

# Every member asks Halon and starts investigations over MCP without a grant, as in Slack and the dashboard. An admin
# can take that away, and a service key holds only what it was granted.
class Mcp::Tools::HalonAccessTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:bob_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    FirefightAi.stubs(:context_window).returns(200_000)
    Conversation::Runner.stubs(:new).returns(
      stub(run: FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_ANSWERED, turns_used: 1, spent_micros: 0),
           reply: "Two deploys went out.")
    )
  end

  test "a member asks Halon and starts an investigation without any grant" do
    asked = call(Mcp::Tools::AskHalon, @member, question: "What changed today?")
    started = call(Mcp::Tools::StartInvestigation, @member, incident: @incident.identifier)

    assert_equal "Two deploys went out.", asked.structured_content[:answer]
    assert_equal @member, @workspace.investigations.find(started.structured_content[:id]).triggered_by
  end

  test "a member an admin took it away from is refused with the sentence every refused tool says, and still reads runs" do
    run = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member, max_turns: 10, max_spend_cents: 400
    )
    take_halon_from(@workspace, @member)

    [ call(Mcp::Tools::AskHalon, @member, question: "What changed today?"),
      call(Mcp::Tools::StartInvestigation, @member, incident: @incident.identifier) ].each do |refused|
      assert refused.error?
      assert_equal "This token lacks 'investigations:create' permission. Token scopes are documented at #{Mcp::Docs::MCP_SERVER}",
                   refused.content.sole[:text]
    end
    assert_equal [ run.id ], @workspace.investigations.pluck(:id)
    assert_equal run.id, call(Mcp::Tools::GetInvestigation, @member, investigation: run.id).structured_content[:id]
  end

  test "a service key without a grant is refused all three, and a grant lets it ask" do
    key = api_keys(:read_only_key)
    run = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: @member, max_turns: 10, max_spend_cents: 400
    )

    { Mcp::Tools::AskHalon => [ { question: "What changed today?" }, "investigations:create" ],
      Mcp::Tools::StartInvestigation => [ { incident: @incident.identifier }, "investigations:create" ],
      Mcp::Tools::GetInvestigation => [ { investigation: run.id }, "investigations:read" ] }.each do |tool, (args, permission)|
      refused = call(tool, key, **args)
      assert refused.error?, tool.name_value
      assert_match "lacks '#{permission}' permission", refused.content.sole[:text]
    end

    Ability::Grant.grant!(workspace: @workspace, principal: key, target: { action: Ability::Action.system!(Ability::Action::INVESTIGATIONS_CREATE) })
    assert_equal "Two deploys went out.", call(Mcp::Tools::AskHalon, key, question: "What changed today?").structured_content[:answer]
  end

  private

  def call(tool, principal, **args)
    Mcp::ToolDispatcher.call(tool: tool, server_context: { workspace: @workspace, principal: principal }, args: args)
  end
end
