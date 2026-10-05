require "test_helper"

class Chat::Tools::IssueFollowUpsTest < ActiveSupport::TestCase
  URL = "https://linear.app/firefight/issue/FIR-105/investigate-automated-probing-against-web-service".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = Incident.create!(
      workspace: @workspace, declared_by: @member, incident_status: incident_statuses(:investigating_ws1),
      incident_severity: incident_severities(:minor_ws1), name: "Automated probing against web", is_private: false,
      channel_id: "C_PROBING", source: Incident::SOURCE_MCP
    )
    linear = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear", slug: "linear",
                                             settings: { "server_url" => "https://mcp.linear.app/mcp" })
    linear.integration_environments.create!
    @save_issue = linear.tools.create!(name: "save_issue", description: "Create or update an issue", read_only: false, enabled: true,
                                       params_schema: { "type" => "object", "properties" => { "id" => {}, "title" => {}, "team" => {}, "state" => {} } })
    stub_post_message
    stub_update_message
    stub_get_permalink
  end

  def chat_about(incident)
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    conversation.update!(subject: incident) if incident
    Conversation::Turn.new(conversation, asker: @member)
  end

  def linear_answers(status_type)
    issue = { "id" => "FIR-105", "title" => "Investigate automated probing against web service", "url" => URL, "statusType" => status_type }
    Integrations::McpExecutor.stubs(:call).returns("content" => [ { "type" => "text", "text" => issue.to_json } ])
  end

  def save_issue(turn, **arguments)
    Chat::Tools::Connection.new(turn, @save_issue).call(**arguments)
  end

  test "an issue opened in a chat about an incident becomes its follow-up with the title and link, and the agent is told" do
    linear_answers("backlog")

    answer = save_issue(chat_about(@incident), team: "FireFight", title: "Investigate automated probing against web service")

    follow_up = @incident.incident_actions.find_by!(external_url: URL)
    assert_equal [ IncidentAction::ACTION_TYPE_FOLLOWUP, "Investigate automated probing against web service", "FIR-105", IncidentAction::STATUS_OPEN ],
                 [ follow_up.action_type, follow_up.description, follow_up.external_key, follow_up.status ]
    assert_equal @member, follow_up.created_by
    assert_match "Firefight recorded FIR-105 on #{@incident.identifier} as a follow-up", answer
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_CREATED)
    assert Ability::Invocation.exists?(action_key: "incidents.update", principal_id: @member.id, incident_id: @incident.id)
  end

  test "the same issue is recorded once, and a chat with no incident records nothing" do
    linear_answers("backlog")
    turn = chat_about(@incident)
    save_issue(turn, team: "FireFight", title: "Investigate")

    assert_no_difference -> { IncidentAction.count } do
      save_issue(turn, team: "FireFight", title: "Investigate")
      save_issue(chat_about(nil), team: "FireFight", title: "Investigate")
    end
  end

  test "closing the issue from any chat completes its open follow-up" do
    follow_up = IncidentActionService.new(@workspace).create_action(
      incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_FOLLOWUP,
      description: "Investigate automated probing against web service", external_key: "FIR-105", external_url: URL
    )
    linear_answers("completed")

    answer = save_issue(chat_about(nil), id: "FIR-105", state: "Done")

    assert follow_up.reload.done?
    assert_match "Firefight marked the follow-up for FIR-105 done on #{@incident.identifier}", answer
  end

  test "a chat that may not update the incident says so and records nothing" do
    linear_answers("backlog")
    AbilityGateway.stubs(:authorize!).with { |principal:, action_key:, **| action_key == "incidents.update" }.raises(AbilityGateway::Denied.new("incidents.update"))
    AbilityGateway.stubs(:authorize!).with { |principal:, action_key:, **| action_key != "incidents.update" }.returns(stub(finalize_success!: nil, invocation_id: nil))

    answer = save_issue(chat_about(@incident), team: "FireFight", title: "Investigate")

    assert_not @incident.incident_actions.exists?
    assert_match "was not recorded on #{@incident.identifier} as a follow-up", answer
  end
end
