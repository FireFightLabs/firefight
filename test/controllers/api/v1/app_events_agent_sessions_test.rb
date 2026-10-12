require "test_helper"

# Linear's app sends its agent sessions, its permission changes and its removal to the app wide address, signed with
# INTEGRATION_LINEAR_WEBHOOK_SECRET, and each reaches the connection made through the organization it names.
class Api::V1::AppEventsAgentSessionsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", settings: {})
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

  test "any other event is taken and left alone" do
    assert_no_enqueued_jobs do
      deliver({ "type" => "AppUserNotification", "action" => "issueMention", "organizationId" => "org-1" })
    end

    assert_response :ok
  end
end
