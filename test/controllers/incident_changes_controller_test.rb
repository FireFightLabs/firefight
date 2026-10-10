require "test_helper"

class IncidentChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!
    @builds = integration.tools.create!(name: "build_history", description: "Builds", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web-id",
                                         name: "web", integration_environment: @row, first_seen_at: 2.days.ago, last_seen_at: Time.current)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, from_value: "a" * 40, to_value: "c" * 40, happened_at: 30.minutes.ago)
    entry = catalog_entries(:auth_service)
    @incident.incident_field_values.create!(incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: entry)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: entry, resource: @web)
  end

  test "what changed on what an incident touches is read when its page opens, and runs only when asked" do
    sign_in(users(:alice), @workspace)
    Integrations::NativeExecutor.expects(:call).never

    get incident_changes_path(@incident)

    body = response.parsed_body
    assert_equal [ "web deployed ccccccc" ], body["entries"].map { |entry| entry["what"] }
    assert_equal [ true, false ], body.values_at("readsRuns", "readLive")

    Integrations::NativeExecutor.unstub(:call)
    run = Integrations::Capabilities::History::Run.new(id: "b1", number: "12", name: "build", status: Integrations::Capabilities::History::SUCCEEDED,
                                                       started_at: 10.minutes.ago)
    Integrations::NativeExecutor.expects(:call).with { |tool:, **| tool == @builds }
                                .returns(Integrations::Capabilities::RunHistory.with_runs({ "content" => [ { "type" => "text", "text" => "1 build" } ] }, [ run ]))

    get incident_changes_path(@incident, live: 1)

    assert_equal "web run #12 build succeeded, from Northflank", response.parsed_body["entries"].first["what"]
    assert Ability::Invocation.exists?(workspace: @workspace, action_key: @builds.action_key, source: AbilityGateway::SOURCE_WEB)
  end

  test "the incident page says whether the person may read the map, which decides whether it shows what changed" do
    sign_in(users(:bob), @workspace)
    get incident_path(@incident), headers: { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s }
    assert_equal true, JSON.parse(response.body).dig("props", "canReadMap")

    WorkspaceMembership.any_instance.stubs(:may?).returns(false)
    get incident_path(@incident), headers: { "X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s }
    assert_equal false, JSON.parse(response.body).dig("props", "canReadMap")
  end
end
