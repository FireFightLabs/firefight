require "test_helper"

# Linear's app sends its agent sessions, its permission changes and its removal to the app wide address, signed with
# INTEGRATION_LINEAR_WEBHOOK_SECRET, and each reaches the connection made through the organization it names.
class Api::V1::AppEventsAgentSessionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "linear", name: "Linear issue sync",
      settings: { "server_url" => "https://mcp.linear.app/mcp", Integration::APP_SETTING => true })
    @row = @integration.integration_environments.create!
    @row.store_installation!("org-1")
    @previous = ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"]
    ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = "app-secret"
  end

  teardown { ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = @previous }

  def deliver(payload, secret: "app-secret", sent_at: Time.current)
    body = payload.merge("webhookTimestamp" => (sent_at.to_f * 1000).to_i).to_json
    post api_v1_app_events_path("linear"), params: body,
                                           headers: { "Linear-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body), "Content-Type" => "application/json" }
  end

  def session_created(organization = "org-1")
    { "type" => "AgentSessionEvent", "action" => "created", "organizationId" => organization, "appUserId" => "app-user", "oauthClientId" => "client",
      "agentSession" => { "id" => "session-1", "issue" => { "identifier" => "ENG-12", "title" => "Checkout", "url" => "https://linear.app/acme/issue/ENG-12" } },
      "promptContext" => "<issue identifier=\"ENG-12\"/>" }
  end

  test "a session signed with the app's secret is taken off the webhook for the connection made through its organization" do
    assert_enqueued_with(job: Integrations::AgentSessionEventJob) { deliver(session_created) }

    assert_response :ok
    job = enqueued_jobs.find { |queued| queued["job_class"] == Integrations::AgentSessionEventJob.name }
    assert_equal "conversations", job["queue_name"]
  end

  test "a session from an organization no connection was made through is taken and left alone" do
    assert_no_enqueued_jobs(only: Integrations::AgentSessionEventJob) { deliver(session_created("org-elsewhere")) }

    assert_response :ok
  end

  test "a connection that is switched off, or one made before the app acted as itself, gets no session" do
    @integration.update!(disabled_at: Time.current)
    assert_no_enqueued_jobs(only: Integrations::AgentSessionEventJob) { deliver(session_created) }

    @integration.update!(disabled_at: nil)
    @row.forget_installation!
    assert_no_enqueued_jobs(only: Integrations::AgentSessionEventJob) { deliver(session_created) }
  end

  test "a delivery the app did not sign, or one older than a minute, is refused" do
    deliver(session_created, secret: "wrong")
    assert_response :unauthorized

    deliver(session_created, sent_at: 2.minutes.ago)
    assert_response :unauthorized
  end

  test "without the app's secret set the address does not exist" do
    ENV["INTEGRATION_LINEAR_WEBHOOK_SECRET"] = nil

    deliver(session_created)

    assert_response :not_found
  end

  test "the app removed from the organization stops the connection, which says to reconnect" do
    deliver({ "type" => "OAuthApp", "action" => "revoked", "organizationId" => "org-1", "oauthClientId" => "client" })

    assert_response :ok
    assert_equal Integrations::Installations::REMOVED, @row.reload.installation_state
    assert_match "Reconnect", Integrations::Installations.stopped_reason(@row)
  end

  test "a change to the teams the app may reach reads the installation again" do
    assert_enqueued_with(job: Integrations::InstallationCheckJob, args: [ @row ]) do
      deliver({ "type" => "PermissionChange", "action" => "teamAccessChanged", "organizationId" => "org-1", "appUserId" => "app-user",
                "canAccessAllPublicTeams" => false, "addedTeamIds" => [], "removedTeamIds" => [ "team-1" ] })
    end

    assert_response :ok
  end

  def labelled(names, organization: "org-1")
    { "type" => "Issue", "action" => "update", "organizationId" => organization, "updatedFrom" => { "labelIds" => [] },
      "actor" => { "id" => "user-2", "type" => "user", "name" => "Bob", "email" => "bob@example.com" },
      "data" => { "id" => "issue-1", "identifier" => "ENG-12", "title" => "Checkout returns 500", "url" => "https://linear.app/acme/issue/ENG-12",
                  "updatedAt" => "2026-10-14T09:00:00.000Z", "labelIds" => names.map { |name| "id-#{name}" },
                  "labels" => names.map { |name| { "id" => "id-#{name}", "name" => name } } } }
  end

  def published(name, trigger)
    alice = workspace_memberships(:alice_workspace_one)
    workflow = Workflow.create!(workspace: @workspace, name: name, created_by: alice)
    draft = workflow.open_draft!(by: alice)
    look = { "id" => "look", "name" => "look", "kind" => "call_tool", "config" => { "tool" => Mcp::Tools::SEARCH_INCIDENTS, "arguments" => { "query" => "{{trigger.issue.title}}" } } }
    draft.update!(trigger: { "kind" => Workflow::Trigger::KIND_ISSUE_ASSIGNED, "inputs" => [] }.merge(trigger), steps: [ look ], edges: [])
    assert_empty draft.problems
    assert WorkflowPublishService.new(workflow).publish!(draft.reload, by: alice).ok
    workflow.reload
  end

  test "a label added to an issue starts the workflows waiting for that label, once, and an assignment still starts every one of them" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    labelled_one = published("Labelled", Workflow::Listening::KEY_LABEL => "firefight")
    other_label = published("Other label", Workflow::Listening::KEY_LABEL => "Triage")
    assigned_only = published("Assigned only", {})
    Conversation::IssueSessions.any_instance.stubs(:asked)

    perform_enqueued_jobs(only: [ WorkflowEventJob, Integrations::AgentSessionEventJob ]) do
      2.times { deliver(labelled([ "Bug", "Firefight" ])) }
      deliver(labelled([ "Bug" ]))
    end

    assert_response :ok
    issue = labelled_one.runs.sole.trigger_payload["issue"]
    assert_equal [ "ENG-12", "Checkout returns 500", "bob@example.com", Workflow::TriggerPayloads::ISSUE_LABELLED, %w[Bug Firefight] ],
                 issue.values_at("key", "title", "asked_by_email", "how", "labels")
    assert_empty other_label.runs
    assert_empty assigned_only.runs

    perform_enqueued_jobs(only: [ WorkflowEventJob, Integrations::AgentSessionEventJob ]) { deliver(session_created) }

    assert_equal [ 2, 1, 1 ], [ labelled_one, other_label, assigned_only ].map { |workflow| workflow.runs.count }
    assert_equal Workflow::TriggerPayloads::ISSUE_ASSIGNED, assigned_only.runs.sole.trigger_payload.dig("issue", "how")
  end

  test "a label added in an organization no connection was made through starts nothing" do
    FeatureFlags.enable!(@workspace, FeatureFlags::WORKFLOWS)
    workflow = published("Labelled", Workflow::Listening::KEY_LABEL => "Firefight")

    perform_enqueued_jobs(only: WorkflowEventJob) { deliver(labelled([ "Firefight" ], organization: "org-elsewhere")) }

    assert_empty workflow.runs
  end

  test "any other event is taken and left alone" do
    assert_no_enqueued_jobs do
      deliver({ "type" => "AppUserNotification", "action" => "issueMention", "organizationId" => "org-1" })
    end

    assert_response :ok
  end
end
