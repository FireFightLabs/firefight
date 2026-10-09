require "test_helper"

class Api::V1::IssueEventsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include IssueTrackerTestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @linear = connect_tracker!(@workspace, provider: "linear")
    sync_with!(@workspace, @linear)
  end

  def change
    { "action" => "update", "type" => "Issue", "updatedFrom" => { "title" => "Old" },
      "data" => { "identifier" => "ENG-12", "title" => "New", "url" => "https://linear.app/acme/issue/ENG-12/new",
                  "updatedAt" => Time.current.utc.iso8601(3), "state" => { "type" => "started" } } }
  end

  test "a change Linear signed with the saved secret is taken, and applied in a job" do
    body, headers = linear_delivery(change)

    assert_enqueued_jobs 1, only: IssueChangeJob do
      post api_v1_issue_events_path(@workspace.issue_webhook_token), params: body, headers: headers
    end
    assert_response :ok
  end

  test "a delivery whose signature fails is refused and nothing is applied" do
    body, headers = linear_delivery(change, secret: "someone else's")

    assert_no_enqueued_jobs do
      post api_v1_issue_events_path(@workspace.issue_webhook_token), params: body, headers: headers
    end
    assert_response :unauthorized
  end

  test "an unknown address, or a workspace without a tracker, is not found" do
    body, headers = linear_delivery(change)
    post api_v1_issue_events_path("nope"), params: body, headers: headers
    assert_response :not_found

    token = @workspace.issue_webhook_token
    @workspace.update!(issue_tracker: nil, issue_creation: Workspace::IssueSync::ISSUE_CREATION_NEVER)
    post api_v1_issue_events_path(token), params: body, headers: headers
    assert_response :not_found
  end

  test "a signed delivery about something else is taken and ignored" do
    body, headers = linear_delivery(change.merge("type" => "Comment"))

    assert_no_enqueued_jobs do
      post api_v1_issue_events_path(@workspace.issue_webhook_token), params: body, headers: headers
    end
    assert_response :ok
  end

  test "a Jira workspace checks Jira's signature" do
    jira = connect_tracker!(@workspace, provider: "jira")
    @workspace.update_settings!(issue_tracker: jira.slug, issue_tracker_target: { "site" => "acme.atlassian.net", "project" => "OPS" }, issue_webhook_secret: "jira-secret")
    payload = { "webhookEvent" => "jira:issue_updated", "timestamp" => (Time.current.to_f * 1000).to_i,
                "issue" => { "key" => "OPS-1", "fields" => { "summary" => "New" } }, "changelog" => { "items" => [ { "field" => "summary" } ] } }

    body, headers = jira_delivery(payload, secret: "jira-secret")
    assert_enqueued_jobs 1, only: IssueChangeJob do
      post api_v1_issue_events_path(@workspace.issue_webhook_token), params: body, headers: headers
    end

    linear_body, linear_headers = linear_delivery(change, secret: "jira-secret")
    post api_v1_issue_events_path(@workspace.issue_webhook_token), params: linear_body, headers: linear_headers
    assert_response :unauthorized
  end

  test "a Jira webhook Firefight registered is proved by Atlassian's token, with no secret pasted" do
    jira = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "jira", name: "Jira issue sync", slug: "jira_issue_sync", settings: {})
    jira.integration_environments.create!(issue_webhook_id: "1000")
    @workspace.update_columns(issue_tracker: jira.slug)
    IntegrationProvider.stubs(:app_client).returns(client_id: "app", client_secret: "app-secret")
    body = { "webhookEvent" => "jira:issue_updated", "timestamp" => (Time.current.to_f * 1000).to_i, "matchedWebhookIds" => [ 1000 ],
             "issue" => { "key" => "OPS-1", "fields" => { "summary" => "New" } }, "changelog" => { "items" => [ { "field" => "summary" } ] } }.to_json

    assert_enqueued_jobs 1, only: IssueChangeJob do
      post api_v1_issue_events_path(@workspace.issue_webhook_token), params: body,
           headers: { "Authorization" => "Bearer #{JWT.encode({}, 'app-secret', 'HS256')}", "Content-Type" => "application/json" }
    end
    assert_response :ok

    post api_v1_issue_events_path(@workspace.issue_webhook_token), params: body,
         headers: { "Authorization" => "Bearer #{JWT.encode({}, 'guess', 'HS256')}", "Content-Type" => "application/json" }
    assert_response :unauthorized
  end
end
