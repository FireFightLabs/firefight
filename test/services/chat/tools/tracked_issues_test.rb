require "test_helper"

class Chat::Tools::TrackedIssuesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
    @get_issue = linear.tools.create!(name: "get_issue", description: "Read an issue", read_only: true, enabled: true,
                                      params_schema: { "type" => "object", "properties" => { "id" => {} } })
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

  test "a tool that opens issues asks how to keep the issue only in a chat about an incident, and never sends the answer on" do
    about = Chat::Tools::Connection.new(chat_about(@incident), @save_issue)
    kind = about.parameters_schema.dig("properties", Chat::Tools::TrackedIssues::KIND_ARG)

    assert_equal IncidentAction::ACTION_TYPES, kind["enum"]
    assert_nil Chat::Tools::Connection.new(chat_about(nil), @save_issue).parameters_schema.dig("properties", Chat::Tools::TrackedIssues::KIND_ARG)
    assert_nil Chat::Tools::Connection.new(chat_about(@incident), @get_issue).parameters_schema.dig("properties", Chat::Tools::TrackedIssues::KIND_ARG)

    linear_answers("backlog")
    Integrations::McpExecutor.expects(:call).with { |arguments:, **| !arguments.key?(Chat::Tools::TrackedIssues::KIND_ARG) }
      .returns("content" => [ { "type" => "text", "text" => { "id" => "FIR-105", "title" => "t", "url" => URL, "statusType" => "backlog" }.to_json } ])
    about.call(team: "FireFight", title: "t", keep_on_incident_as: "followup")
  end

  test "an issue opened during a live incident is an action unless Halon says it is a follow-up, with the title and link" do
    linear_answers("backlog")

    answer = save_issue(chat_about(@incident), team: "FireFight", title: "Investigate automated probing against web service")

    item = @incident.incident_actions.find_by!(external_url: URL)
    assert_equal [ IncidentAction::ACTION_TYPE_ACTION, "Investigate automated probing against web service", "FIR-105", IncidentAction::STATUS_OPEN ],
                 [ item.action_type, item.description, item.external_key, item.status ]
    assert_equal @member, item.created_by
    assert_match "Firefight recorded FIR-105 on #{@incident.identifier} as an action", answer
    assert @incident.incident_events.exists?(event_type: IncidentEvent::ACTION_CREATED)
    assert Ability::Invocation.exists?(action_key: "incidents.update", principal_id: @member.id, incident_id: @incident.id)

    item.destroy!
    save_issue(chat_about(@incident), team: "FireFight", title: "Harden the origin", keep_on_incident_as: "followup")
    assert_equal IncidentAction::ACTION_TYPE_FOLLOWUP, @incident.incident_actions.find_by!(external_url: URL).action_type
  end

  test "once the incident is over the issue is a follow-up, and asking for an action says why it is not one" do
    linear_answers("backlog")
    @incident.update!(incident_status: incident_statuses(:resolved_ws1), resolved_at: Time.current)

    answer = save_issue(chat_about(@incident), team: "FireFight", title: "Investigate", keep_on_incident_as: "action")

    assert_equal IncidentAction::ACTION_TYPE_FOLLOWUP, @incident.incident_actions.find_by!(external_url: URL).action_type
    assert_match "as a follow-up with its link", answer
    assert_match "rather than an action, since #{@incident.identifier} is over", answer
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

  test "closing the issue from any chat completes the action or follow-up that tracks it" do
    service = IncidentActionService.new(@workspace)
    action = service.create_action(incident: @incident, created_by: @member, action_type: IncidentAction::ACTION_TYPE_ACTION,
                                   description: "Investigate", external_key: "FIR-105", external_url: URL)
    linear_answers("completed")

    answer = save_issue(chat_about(nil), id: "FIR-105", state: "Done")

    assert action.reload.done?
    assert_match "Firefight marked the action on #{@incident.identifier} for FIR-105 done", answer
  end

  test "a chat that may not update the incident says so and records nothing" do
    linear_answers("backlog")
    AbilityGateway.stubs(:authorize!).with { |principal:, action_key:, **| action_key == "incidents.update" }.raises(AbilityGateway::Denied.new("incidents.update"))
    AbilityGateway.stubs(:authorize!).with { |principal:, action_key:, **| action_key != "incidents.update" }.returns(stub_everything(invocation_id: nil))

    answer = save_issue(chat_about(@incident), team: "FireFight", title: "Investigate")

    assert_not @incident.incident_actions.exists?
    assert_match "was not recorded on #{@incident.identifier}", answer
  end

  test "an issue opened in a chat is kept in step with its follow-up, and closing it there is not sent back" do
    linear_answers("backlog")
    save_issue(chat_about(@incident), team: "FireFight", title: "Investigate")
    follow_up = @incident.incident_actions.find_by!(external_url: URL)
    assert_equal [ @save_issue.integration, IncidentAction::ISSUE_LINKED ], [ follow_up.issue_integration, follow_up.issue_sync_state ]

    @workspace.update!(issue_tracker: "linear", issue_tracker_target: { "team" => "FireFight" })
    assert follow_up.issue_syncs?
    linear_answers("completed")
    assert_no_enqueued_jobs(only: IssueSyncJob) do
      save_issue(chat_about(nil), id: "FIR-105", state: "Done")
    end
    assert follow_up.reload.done?
  end
end
