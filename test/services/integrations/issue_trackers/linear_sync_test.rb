require "test_helper"

module Integrations
  module IssueTrackers
    # Keeping an item in step with a Linear issue. Answers are shaped as Linear's hosted server gives save_issue's (see
    # linear_test.rb), and webhook deliveries as https://linear.app/developers/webhooks documents a data change event,
    # with the issue's fields as IssueWebhookPayload in the SDK's schema.graphql.
    class LinearSyncTest < ActiveSupport::TestCase
      include IssueTrackerTestHelper

      ISSUE = { "id" => "ENG-12", "title" => "Rotate the database password", "url" => "https://linear.app/acme/issue/ENG-12/rotate",
                "statusType" => "backlog" }.freeze
      STATUSES = [ { "id" => "s-backlog", "type" => "backlog" }, { "id" => "s-todo", "type" => "unstarted" },
                   { "id" => "s-doing", "type" => "started" }, { "id" => "s-done", "type" => "completed" } ].freeze

      def tracker(tools: nil, **answers)
        tools ||= answers.keys
        calls = []
        reader = Linear.new(nil, tools.index_with { |_name| Struct.new(:params_schema).new({ "properties" => {} }) }) do |name, arguments, _reads|
          calls << [ name, arguments ]
          answers[name]
        end
        [ reader, calls ]
      end

      test "an issue is opened in the team with the title, the description and the person whose email matches" do
        reader, calls = tracker("list_users" => json_answer([ { "id" => "u-1", "email" => "Alice@Example.com" } ]), "save_issue" => json_answer(ISSUE))

        outcome = reader.create(title: "Rotate the database password", description: "From INC-1.", target: { "team" => "ENG" }, assignee_email: "alice@example.com")

        assert_equal [ "ENG-12", ISSUE["url"], Integrations::Issues::STATE_OPEN ], [ outcome.issue.key, outcome.issue.url, outcome.issue.state ]
        assert_empty outcome.notes
        assert_equal({ "title" => "Rotate the database password", "team" => "ENG", "description" => "From INC-1.", "assignee" => "u-1" }, calls.last.last)
      end

      test "a person Linear has no account for is left off the issue, and the outcome says so" do
        reader, calls = tracker("list_users" => json_answer([ { "id" => "u-2", "email" => "someone@example.com" } ]), "save_issue" => json_answer(ISSUE))

        outcome = reader.create(title: "Rotate", description: "", target: { "team" => "ENG" }, assignee_email: "alice@example.com")

        assert_not calls.last.last.key?("assignee")
        assert_match "Linear has nobody with the email alice@example.com", outcome.notes.first
      end

      test "opening refuses without a team, and says Linear's own words when it refuses" do
        reader, = tracker("save_issue" => error_answer("Team not found"))

        assert_raises(Integrations::Issues::Failed) { reader.create(title: "x", description: "", target: {}) }
        error = assert_raises(Integrations::Issues::Failed) { reader.create(title: "x", description: "", target: { "team" => "NOPE" }) }
        assert_equal "Linear refused to open the issue: Team not found.", error.message
      end

      test "a tool that is switched off is named, so an admin knows what to switch on" do
        reader, = tracker(tools: [])

        error = assert_raises(Integrations::Issues::Failed) { reader.create(title: "x", description: "", target: { "team" => "ENG" }) }
        assert_match "save_issue is switched off for Linear", error.message
      end

      test "a status is set by the first of the team's states of its documented type" do
        reader, calls = tracker("list_issue_statuses" => json_answer(STATUSES), "save_issue" => json_answer(ISSUE))

        reader.update(key: "ENG-12", target: { "team" => "ENG" }, state: Integrations::Issues::STATE_STARTED)
        assert_equal({ "id" => "ENG-12", "state" => "s-doing" }, calls.last.last)

        reader.update(key: "ENG-12", target: { "team" => "ENG" }, state: Integrations::Issues::STATE_DONE, title: "Renamed")
        assert_equal({ "id" => "ENG-12", "title" => "Renamed", "state" => "s-done" }, calls.last.last)
      end

      test "an issue Linear no longer has is gone, for an update and a read" do
        reader, = tracker("save_issue" => error_answer("Entity not found: Issue"), "get_issue" => error_answer("Could not find the issue"))

        assert reader.update(key: "ENG-12", target: { "team" => "ENG" }, title: "x").gone
        assert_nil reader.read("ENG-12")
      end

      test "a delivery counts only with Linear's signature over the raw body, sent within the minute" do
        body, headers = linear_delivery({ "type" => "Issue" })

        assert Linear.verify(raw_body: body, headers: headers, secret: "whsec")
        assert_not Linear.verify(raw_body: body, headers: headers, secret: "another")
        assert_not Linear.verify(raw_body: body.sub("Issue", "Comment"), headers: headers, secret: "whsec")
        assert_not Linear.verify(raw_body: body, headers: {}, secret: "whsec")

        travel_to 2.minutes.from_now do
          assert_not Linear.verify(raw_body: body, headers: headers, secret: "whsec")
        end
      end

      def payload(data, updated_from, action: "update")
        { "action" => action, "type" => "Issue", "updatedFrom" => updated_from,
          "data" => { "id" => "uuid-1", "identifier" => "ENG-12", "previousIdentifiers" => [ "OPS-3" ], "title" => "Rotate it",
                      "url" => ISSUE["url"], "updatedAt" => "2026-10-05T10:00:00.000Z", "state" => { "type" => "completed" },
                      "assignee" => { "name" => "Alice", "email" => "alice@example.com" } }.merge(data) }
      end

      test "an update names only what changed, with the issue as it now is" do
        event = Linear.event(payload({}, { "stateId" => "s-doing", "title" => "Old", "updatedAt" => "x" }))

        assert_equal [ "ENG-12", "OPS-3" ], event.keys
        assert_equal [ Integrations::Issues::FIELD_STATE, Integrations::Issues::FIELD_TITLE ].sort, event.changed.sort
        assert_equal [ Integrations::Issues::STATE_DONE, "Rotate it", "alice@example.com" ], [ event.state, event.title, event.assignee_email ]
        assert_equal Time.utc(2026, 10, 5, 10), event.at
      end

      test "a canceled issue is done, a started one started and a triaged or backlog one open" do
        assert_equal Integrations::Issues::STATE_DONE, Linear.state_of("canceled")
        assert_equal Integrations::Issues::STATE_STARTED, Linear.state_of("started")
        assert_equal Integrations::Issues::STATE_OPEN, Linear.state_of("triage")
        assert_equal Integrations::Issues::STATE_OPEN, Linear.state_of("backlog")
      end

      test "a removed, trashed or archived issue is gone, and anything else is not an event" do
        assert_equal Integrations::Issues::GONE_DELETED, Linear.event(payload({}, nil, action: "remove")).gone
        assert_equal Integrations::Issues::GONE_DELETED, Linear.event(payload({ "trashed" => true }, { "trashed" => nil })).gone
        assert_equal Integrations::Issues::GONE_ARCHIVED, Linear.event(payload({ "archivedAt" => "2026-10-05T10:00:00Z" }, { "archivedAt" => nil })).gone
        assert_nil Linear.event(payload({}, { "priority" => 2 }))
        assert_nil Linear.event(payload({}, nil, action: "create"))
        assert_nil Linear.event(payload({}, { "title" => "x" }).merge("type" => "Comment"))
      end
    end
  end
end
