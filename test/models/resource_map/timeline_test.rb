require "test_helper"

class ResourceMap::TimelineTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    @restart = integration.tools.create!(name: "restart_service", description: "Restart", read_only: false, enabled: true, params_schema: { "type" => "object" })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                         name: "web", url: "https://app.northflank.com/s/acme/shop/services/web", integration_environment: @row,
                                         first_seen_at: 2.days.ago, last_seen_at: Time.current)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, from_value: "aaaaaaa1", to_value: "bbbbbbb2", happened_at: 2.hours.ago)
  end

  test "an admin reads deploys, a provider's report and a change through Firefight in one list, newest first, each linked" do
    restarted!(at: 50.minutes.ago)
    reported!(at: 20.minutes.ago)

    entries = timeline(@admin).entries

    assert_equal [ ResourceMap::Timeline::KIND_REPORTED, ResourceMap::Timeline::KIND_FIREFIGHT, ResourceMap::Timeline::KIND_DEPLOY ], entries.map(&:kind)
    assert_equal "web deployed bbbbbbb", entries.last.what
    assert_equal @web.url, entries.last.link
    assert_equal "Northflank reported web changed, #{ResourceMap::Timeline::HAND_EDIT}", entries.first.what
    firefight = entries.second
    assert_equal [ "Alice", "Northflank" ], [ firefight.by, firefight.where ]
    assert_match "Restart service through Northflank, from Halon chat", firefight.what
    assert_match "/gateway/activity", firefight.link
  end

  test "a report just after a change made through Firefight is not taken for a hand edit, and a burst of reports is one entry" do
    restarted!(at: 3.minutes.ago)
    3.times { |index| reported!(at: (2.minutes - (index * 20).seconds).ago, id: "event-#{index}") }

    reported = timeline(@admin).entries.select { |entry| entry.kind == ResourceMap::Timeline::KIND_REPORTED }

    assert_equal 1, reported.size
    assert_match(/\ANorthflank reported web changed 3 times up to \S+\z/, reported.sole.what)
  end

  test "someone who may not read the activity log is told changes through Firefight are left out, and no report is called a hand edit" do
    restarted!(at: 50.minutes.ago)
    reported!(at: 20.minutes.ago)

    listed = timeline(@member)

    assert_equal [ ResourceMap::Timeline::KIND_REPORTED, ResourceMap::Timeline::KIND_DEPLOY ], listed.entries.map(&:kind)
    assert_equal "Northflank reported web changed", listed.entries.first.what
    assert_includes listed.notes, "Changes made through Firefight are left out, since only those who may read the activity log see them."
  end

  test "the text says what changed in the window, and what the list could not cover" do
    text = timeline(@admin).text(read: [ "The runs of web could not be read: down" ])

    assert_match(/\AWhat changed for web from \S+ to \S+, newest first:\n- \S+ Deploy: web deployed bbbbbbb #{Regexp.escape(@web.url)}/, text)
    assert_match "Not in this list:\n- The runs of web could not be read: down", text
    assert_match "Northflank is read at the hourly sweep", text
  end

  test "a run read live sits in the list with its link" do
    run = { "id" => "r1", "number" => "46", "name" => "release", "status" => "failed", "started_at" => 30.minutes.ago.iso8601,
            "seconds" => 190, "url" => "https://app.northflank.com/runs/46", "detail" => "a1b2c3d" }
    entry = ResourceMap::Timeline.run_entry(@web, run, through: "Northflank")

    assert_equal "web run #46 release failed, took 3 minutes and 10 seconds (a1b2c3d), from Northflank", entry.what
    assert_equal [ ResourceMap::Timeline::KIND_RUN, ResourceMap::Timeline::KIND_DEPLOY ], timeline(@admin).entries(live: [ entry ]).map(&:kind)
  end

  test "a service is every resource that runs it, and one the catalog does not hold is refused in words" do
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @web)

    subject = ResourceMap::Timeline.subject(@workspace, @admin, ResourceMap::Timeline::SERVICE_ARG => "auth service")

    assert_equal [ ResourceMap::Timeline::SUBJECT_SERVICE, [ @web ] ], [ subject.kind, subject.resources ]
    assert_match "Nothing in the catalog is called billing", ResourceMap::Timeline.subject(@workspace, @admin, ResourceMap::Timeline::SERVICE_ARG => "billing")
  end

  test "the whole workspace reads no runs live, says so, and names where feature flags are kept" do
    @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "posthog", name: "PostHog", slug: "posthog")
    listed = ResourceMap::Timeline.new(workspace: @workspace, principal: @admin, subject: ResourceMap::Timeline.subject(@workspace, @admin, {}),
                                       from: 1.day.ago, to: Time.current)

    assert_empty listed.live_targets
    assert_equal [ "web deployed bbbbbbb" ], listed.entries.map(&:what)
    assert(listed.notes.any? { |note| note.start_with?("Runs are read live only for one resource or service") })
    assert(listed.notes.any? { |note| note.start_with?("Feature flag changes are kept at PostHog") })
  end

  test "a window is minutes back from now or a start and end, never backwards and never past thirty days" do
    now = Time.zone.parse("2026-10-10T10:00:00Z")

    assert_equal [ now - 1.day, now ], ResourceMap::Timeline.window({}, now: now)
    assert_equal [ now - 90.minutes, now ], ResourceMap::Timeline.window({ "minutes" => 90 }, now: now)
    assert_raises(ArgumentError) { ResourceMap::Timeline.window({ "start" => "2026-10-10T11:00:00Z" }, now: now) }
    assert_raises(ArgumentError) { ResourceMap::Timeline.window({ "minutes" => 31 * 24 * 60 }, now: now) }
    error = assert_raises(ArgumentError) { ResourceMap::Timeline.window({ "start" => "yesterday" }, now: now) }
    assert_match "ISO 8601", error.message
  end

  private

  def timeline(principal)
    subject = ResourceMap::Timeline.subject(@workspace, principal, ResourceMap::Timeline::RESOURCE_ARG => "web")
    ResourceMap::Timeline.new(workspace: @workspace, principal: principal, subject: subject, from: 1.day.ago, to: Time.current)
  end

  def restarted!(at:)
    Ability::Invocation.create!(workspace: @workspace, principal: @admin, principal_label: "Alice", action_key: @restart.action_key,
                                decision: Ability::Invocation::DECISION_ALLOW, outcome: Ability::Invocation::OUTCOME_SUCCESS,
                                risk_level: Ability::Action::RISK_WRITE, source: AbilityGateway::SOURCE_CONVERSATION,
                                params: { "service" => "web-id" }, idempotency_key: SecureRandom.uuid, created_at: at, completed_at: at)
  end

  def reported!(at:, id: SecureRandom.uuid)
    scope = ResourceMap::Scope.new(account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web-id")
    ResourceMap::ReceivedEvent.create!(workspace: @workspace, integration_environment: @row, provider_event_id: id, action: ResourceMap::Event::UPDATED,
                                       scope: scope.to_job, scope_key: scope.key, happened_at: at, received_at: at,
                                       outcome: ResourceMap::ReceivedEvent::OUTCOME_APPLIED)
  end
end
