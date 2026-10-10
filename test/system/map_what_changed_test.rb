require "application_system_test_case"

class MapWhatChangedTest < ApplicationSystemTestCase
  History = Integrations::Capabilities::History

  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = integration.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @builds = integration.tools.create!(name: "build_history", description: "Builds", read_only: true, enabled: true, params_schema: { "type" => "object" })
    restart = integration.tools.create!(name: "restart_service", description: "Restart", read_only: false, enabled: true, params_schema: { "type" => "object" })
    ResourceMap.record!(@row, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web",
                             url: "https://app.northflank.com/s/acme/shop/services/web")
    ]))
    @web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, from_value: "a" * 40, to_value: "9f1c2e7" + ("b" * 33), happened_at: 3.hours.ago)
    scope = ResourceMap::Scope.new(account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web")
    ResourceMap::ReceivedEvent.create!(workspace: @workspace, integration_environment: @row, provider_event_id: "e1", action: ResourceMap::Event::UPDATED,
                                       scope: scope.to_job, scope_key: scope.key, happened_at: 40.minutes.ago, received_at: 40.minutes.ago,
                                       outcome: ResourceMap::ReceivedEvent::OUTCOME_APPLIED)
    Ability::Invocation.create!(workspace: @workspace, principal: workspace_memberships(:alice_workspace_one), principal_label: "Alice",
                                action_key: restart.action_key, decision: Ability::Invocation::DECISION_ALLOW, outcome: Ability::Invocation::OUTCOME_SUCCESS,
                                risk_level: Ability::Action::RISK_WRITE, source: AbilityGateway::SOURCE_CONVERSATION, params: { "service" => "web" },
                                idempotency_key: SecureRandom.uuid, created_at: 2.hours.ago, completed_at: 2.hours.ago)
  end

  test "a resource's panel lists what changed from every source, and reads its runs from the provider when asked" do
    run = History::Run.new(id: "b46", number: "46", name: "build", status: History::FAILED, started_at: 12.minutes.ago, finished_at: 9.minutes.ago,
                           url: "https://app.northflank.com/builds/46")
    Integrations::NativeExecutor.stubs(:call).returns(Integrations::Capabilities::RunHistory.with_runs({ "content" => [ { "type" => "text", "text" => "1 build" } ] }, [ run ]))

    visit resource_map_path(ResourceMap::PAGE_VIEW_PARAM => "focus", ResourceMap::PAGE_RESOURCE_PARAM => @web.id)

    within("aside[aria-label='About web']") do
      assert_text(/what changed/i)
      assert_text "web appeared\n1m ago"
      assert_text "Northflank reported web changed, and nothing in Firefight's activity log matches it"
      assert_text "Restart service through Northflank, from Halon chat"
      assert_text "web deployed 9f1c2e7"
      assert_text "Deploys and runs here are the ones the map saw."
      click_on "Read runs now"
      assert_text "web run #46 build failed, took 3 minutes, from Northflank"
      assert_text "Runs were read just now."
      assert_button "Read again"
    end
  end

  test "an incident's page lists what changed on what it touches, and reads its runs when asked" do
    incident = incidents(:active_critical_ws1)
    entry = catalog_entries(:auth_service)
    incident.incident_field_values.create!(incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: entry)
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: entry, resource: @web)
    incident.update_columns(declared_at: 1.hour.ago, detected_at: nil)
    run = History::Run.new(id: "b47", number: "47", name: "build", status: History::SUCCEEDED, started_at: 20.minutes.ago, finished_at: 16.minutes.ago)
    Integrations::NativeExecutor.stubs(:call).returns(Integrations::Capabilities::RunHistory.with_runs({ "content" => [ { "type" => "text", "text" => "1 build" } ] }, [ run ]))

    visit incident_path(incident)

    assert_text "Northflank reported web changed"
    assert_no_text "web deployed 9f1c2e7"
    click_on "Read runs now"
    assert_text "web run #47 build succeeded, took 4 minutes, from Northflank"
  end
end
