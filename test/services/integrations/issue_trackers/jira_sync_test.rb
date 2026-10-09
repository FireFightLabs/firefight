require "test_helper"

module Integrations
  module IssueTrackers
    # Keeping an item in step with a Jira issue, through Atlassian's server with the site's address as cloudId. Webhook
    # deliveries are shaped as https://developer.atlassian.com/cloud/jira/platform/webhooks/ documents an issue event.
    class JiraSyncTest < ActiveSupport::TestCase
      include IssueTrackerTestHelper

      TARGET = { "site" => "acme.atlassian.net", "project" => "ops" }.freeze
      TRANSITIONS = { "transitions" => [
        { "id" => "11", "name" => "To Do", "to" => { "statusCategory" => { "key" => "new" } } },
        { "id" => "21", "name" => "In Progress", "to" => { "statusCategory" => { "key" => "indeterminate" } } },
        { "id" => "31", "name" => "Done", "to" => { "statusCategory" => { "key" => "done" } } }
      ] }.freeze

      def tracker(tools: nil, **answers)
        tools ||= answers.keys
        calls = []
        reader = Jira.new(nil, tools.index_with { |_name| Struct.new(:params_schema).new({ "properties" => {} }) }) do |name, arguments, _reads|
          calls << [ name, arguments ]
          answers[name]
        end
        [ reader, calls ]
      end

      test "an issue is opened in the project with the type, summary and the account whose email matches" do
        reader, calls = tracker("lookupjiraaccountid" => json_answer([ { "accountId" => "acc-1", "emailAddress" => "alice@example.com" } ]),
                                "createjiraissue" => json_answer({ "id" => "10001", "key" => "OPS-42" }))

        outcome = reader.create(title: "Rotate the password", description: "From INC-1.", target: TARGET, assignee_email: "alice@example.com")

        assert_equal [ "OPS-42", "https://acme.atlassian.net/browse/OPS-42" ], [ outcome.issue.key, outcome.issue.url ]
        assert_equal({ "cloudId" => "acme.atlassian.net", "projectKey" => "OPS", "issueType" => "Task", "summary" => "Rotate the password",
                       "description" => "From INC-1.", "assignee" => "acc-1" }, calls.last.last)
        assert_equal({ "cloudId" => "acme.atlassian.net", "query" => "alice@example.com" }, calls.first.last)
      end

      test "an account whose email Jira hides is no match, and the outcome says so" do
        reader, calls = tracker("lookupjiraaccountid" => json_answer([ { "accountId" => "acc-1", "displayName" => "Alice" } ]),
                                "createjiraissue" => json_answer({ "key" => "OPS-42" }))

        outcome = reader.create(title: "x", description: "", target: TARGET, assignee_email: "alice@example.com")

        assert_not calls.last.last.key?("assignee")
        assert_match "Jira has nobody whose email shows as alice@example.com", outcome.notes.first
      end

      test "a status moves through the first transition into its category, and the summary and assignee are edited" do
        reader, calls = tracker("listjiraissuetransitions" => json_answer(TRANSITIONS), "transitionjiraissue" => text_answer("Done."),
                                "editjiraissue" => text_answer("Updated."),
                                "lookupjiraaccountid" => json_answer({ "users" => [ { "accountId" => "acc-2", "emailAddress" => "bob@example.com" } ] }))

        reader.update(key: "OPS-42", target: TARGET, title: "Renamed", assignee_email: "bob@example.com", state: Integrations::Issues::STATE_STARTED)

        edit = calls.find { |name, _| name == "editjiraissue" }.last
        assert_equal({ "summary" => "Renamed", "assignee" => { "accountId" => "acc-2" } }, edit["fields"])
        assert_equal({ "id" => "21" }, calls.last.last["transition"])
      end

      test "with no transition into the category the status is left alone and the outcome says so" do
        reader, calls = tracker("listjiraissuetransitions" => json_answer({ "transitions" => [] }))

        outcome = reader.update(key: "OPS-42", target: TARGET, state: Integrations::Issues::STATE_DONE)

        assert_equal [ "listjiraissuetransitions" ], calls.map(&:first)
        assert_match "No transition from OPS-42's status leads to a done status", outcome.notes.first
      end

      test "an issue Jira no longer has is gone" do
        reader, = tracker("editjiraissue" => error_answer("Issue does not exist or you do not have permission to see it."),
                          "getjiraissue" => error_answer("Issue does not exist"))

        assert reader.update(key: "OPS-42", target: TARGET, title: "x").gone
        assert_nil reader.read("OPS-42", target: TARGET)
      end

      test "a change refused for something else it names fails with Jira's words, and the issue stays kept" do
        reader, = tracker("editjiraissue" => error_answer("Field 'customfield_1' does not exist."), "getjiraissue" => json_answer({ "key" => "OPS-42", "fields" => {} }),
                          "listjiraissuetransitions" => error_answer("Status not found"))

        assert_raises(Integrations::Issues::Failed) { reader.update(key: "OPS-42", target: TARGET, title: "x") }
        assert_raises(Integrations::Issues::Failed) { reader.update(key: "OPS-42", target: TARGET, state: Integrations::Issues::STATE_DONE) }
      end

      test "a delivery counts only with Jira's sha256 signature over the raw body" do
        body, headers = jira_delivery({ "webhookEvent" => "jira:issue_updated" })

        assert Jira.verify(raw_body: body, headers: headers, secret: "whsec")
        assert_not Jira.verify(raw_body: body, headers: headers, secret: "another")
        assert_not Jira.verify(raw_body: body, headers: { "X-Hub-Signature" => headers["X-Hub-Signature"].delete_prefix("sha256=") }, secret: "whsec")
        assert_not Jira.verify(raw_body: "#{body} ", headers: headers, secret: "whsec")
      end

      def payload(items, event: "jira:issue_updated")
        { "webhookEvent" => event, "timestamp" => 1_791_194_400_000,
          "issue" => { "key" => "OPS-42", "fields" => { "summary" => "Rotate it", "status" => { "statusCategory" => { "key" => "done" } },
                                                        "assignee" => { "displayName" => "Bob", "emailAddress" => "bob@example.com" } } },
          "changelog" => { "items" => items } }
      end

      test "an update names only the changed fields Firefight keeps, and a moved issue keeps its old key" do
        event = Jira.event(payload([ { "field" => "status" }, { "field" => "Key", "fromString" => "OLD-1", "toString" => "OPS-42" },
                                     { "field" => "priority" } ]))

        assert_equal [ "OPS-42", "OLD-1" ], event.keys
        assert_equal [ Integrations::Issues::FIELD_STATE ], event.changed
        assert_equal [ Integrations::Issues::STATE_DONE, "bob@example.com", "Bob" ], [ event.state, event.assignee_email, event.assignee_name ]
        assert_equal Time.at(1_791_194_400).utc, event.at
      end

      test "a deleted issue is gone, and a change to nothing Firefight keeps or another event is no event" do
        assert_equal Integrations::Issues::GONE_DELETED, Jira.event(payload([], event: "jira:issue_deleted")).gone
        assert_nil Jira.event(payload([ { "field" => "priority" } ]))
        assert_nil Jira.event(payload([ { "field" => "summary" } ], event: "comment_created"))
      end

      test "status categories map to Firefight's states" do
        assert_equal Integrations::Issues::STATE_OPEN, Jira.state_of("new")
        assert_equal Integrations::Issues::STATE_STARTED, Jira.state_of("indeterminate")
        assert_equal Integrations::Issues::STATE_DONE, Jira.state_of("done")
      end

      test "a webhook Firefight registered is proved by Atlassian's token signed with the app's secret and naming that webhook" do
        body = { "webhookEvent" => "jira:issue_updated", "matchedWebhookIds" => [ 1000 ] }.to_json
        IntegrationProvider.stubs(:app_client).with("jira").returns(client_id: "app", client_secret: "app-secret")
        signed = { "Authorization" => "Bearer #{JWT.encode({ 'iss' => 'atlassian' }, 'app-secret', 'HS256')}" }

        assert Jira.verify(raw_body: body, headers: signed, secret: nil, webhook_id: "1000")
        assert_not Jira.verify(raw_body: body, headers: signed, secret: nil, webhook_id: "2000")
        assert_not Jira.verify(raw_body: body, headers: { "Authorization" => "Bearer #{JWT.encode({}, 'other', 'HS256')}" }, secret: nil, webhook_id: "1000")
        assert_not Jira.verify(raw_body: body, headers: {}, secret: nil, webhook_id: "1000")
      end
    end
  end
end
