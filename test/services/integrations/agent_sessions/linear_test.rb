require "test_helper"

module Integrations
  module AgentSessions
    # Linear's AgentSessionEvent, PermissionChange and OAuthApp deliveries, read as the schema's webhook payloads name them,
    # and the activities Halon posts back through agentActivityCreate.
    class LinearTest < ActiveSupport::TestCase
      SESSION = {
        "id" => "session-1", "appUserId" => "app-user", "organizationId" => "org-1", "status" => "pending", "type" => "issue",
        "issue" => { "id" => "issue-1", "identifier" => "ENG-12", "title" => "Checkout returns 500", "url" => "https://linear.app/acme/issue/ENG-12/checkout",
                     "description" => "Since 14:00", "teamId" => "team-1" },
        "comment" => { "id" => "comment-1", "body" => "@firefight why is checkout failing?" },
        "creator" => { "id" => "user-1", "name" => "Alice", "email" => "alice@example.com" }
      }.freeze

      def created(**changes)
        { "type" => Linear::TYPE_SESSION, "action" => "created", "organizationId" => "org-1", "agentSession" => SESSION,
          "promptContext" => "<issue identifier=\"ENG-12\"><title>Checkout returns 500</title></issue>", "webhookTimestamp" => 1 }.merge(changes)
      end

      def prompted(activity)
        { "type" => Linear::TYPE_SESSION, "action" => "prompted", "organizationId" => "org-1", "agentSession" => SESSION, "agentActivity" => activity }
      end

      test "a new session is the person's comment with Linear's own account of the issue, and who asked" do
        event = Linear.event(created)

        assert_equal [ STARTED, "session-1", "@firefight why is checkout failing?" ], [ event.kind, event.session_id, event.text ]
        assert_equal [ "ENG-12", "Checkout returns 500", SESSION["issue"]["url"] ], [ event.issue_key, event.issue_title, event.issue_url ]
        assert_equal [ "alice@example.com", "Alice" ], [ event.asker_email, event.asker_name ]
        assert_match "<issue identifier=\"ENG-12\">", event.context
        assert_equal event, Event.from_job(event.to_job)
      end

      test "a session opened by delegating the issue has no words of its own" do
        assert_nil Linear.event(created("agentSession" => SESSION.except("comment"))).text
      end

      test "a follow up is its content's body, and a stop request is the stop signal" do
        follow_up = Linear.event(prompted("content" => { "type" => "prompt", "body" => "And the payments service?" }, "user" => { "email" => "bob@example.com" }))
        stop = Linear.event(prompted("content" => { "type" => "prompt", "body" => "" }, "signal" => "stop"))

        assert_equal [ PROMPTED, "And the payments service?", "bob@example.com" ], [ follow_up.kind, follow_up.text, follow_up.asker_email ]
        assert_equal [ STOPPED, "session-1" ], [ stop.kind, stop.session_id ]
      end

      test "anything else is left alone" do
        assert_nil Linear.event(created("action" => "updated"))
        assert_nil Linear.event({ "type" => "Issue", "action" => "update", "data" => {} })
        assert_nil Linear.event(prompted("content" => { "body" => " " }))
      end

      test "the installation is the organization, removed when the app is revoked and read again when its teams change" do
        revoked = { "type" => "OAuthApp", "action" => "revoked", "organizationId" => "org-1", "oauthClientId" => "client" }
        teams = { "type" => "PermissionChange", "action" => "teamAccessChanged", "organizationId" => "org-1", "addedTeamIds" => [], "removedTeamIds" => [ "team-1" ] }

        assert_equal "org-1", Linear.installation_of(revoked, headers: {})
        assert_equal Installations::CHANGE_REMOVED, Linear.installation_change(revoked, headers: {})
        assert_equal Installations::CHANGE_REACH, Linear.installation_change(teams, headers: {})
        assert_nil Linear.installation_change(created, headers: {})
      end

      test "a delivery counts only when signed with the app's secret within a minute" do
        body = created("webhookTimestamp" => (Time.current.to_f * 1000).to_i).to_json
        signed = { "Linear-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "app-secret", body) }

        assert Linear.verify(raw_body: body, headers: signed, secret: "app-secret")
        assert_not Linear.verify(raw_body: body, headers: signed, secret: "other")
        stale = created("webhookTimestamp" => 2.minutes.ago.to_i * 1000).to_json
        assert_not Linear.verify(raw_body: stale, headers: { "Linear-Signature" => OpenSSL::HMAC.hexdigest("SHA256", "app-secret", stale) }, secret: "app-secret")
      end

      test "an activity is posted in the session's shape, and the session points at its chat" do
        workspace = workspaces(:slack_workspace_one)
        row = workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", settings: {})
                       .integration_environments.create!
        Credentials.stubs(:headers_for).returns("Authorization" => "Bearer lin_app")
        LinearApi.any_instance.expects(:create_activity).with({
          "agentSessionId" => "session-1", "content" => { "type" => ACTION, "action" => "Search logs", "parameter" => "checkout errors" }, "ephemeral" => true
        }).returns(true)
        LinearApi.any_instance.expects(:update_session).with("session-1", { "externalUrls" => [ { "label" => "Open in Firefight", "url" => "https://ff.example.com/agent/1" } ] })

        session = AgentSessions.for(row)
        session.say("session-1", Activity.new(kind: ACTION, action: "Search logs", parameter: "checkout errors", ephemeral: true))
        session.link("session-1", label: "Open in Firefight", url: "https://ff.example.com/agent/1")
      end

      test "Linear's refusal is said in words" do
        row = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_NATIVE, provider: "linear", name: "Linear issue sync", settings: {})
                                              .integration_environments.create!
        Credentials.stubs(:headers_for).returns({})
        LinearApi.any_instance.stubs(:create_activity).raises(LinearApi::Error, "Linear refused this: Agent session not found")

        error = assert_raises(Integrations::Error) { AgentSessions.for(row).say("gone", Activity.new(kind: THOUGHT, body: "On it.")) }
        assert_match "Agent session not found", error.message
      end
    end
  end
end
