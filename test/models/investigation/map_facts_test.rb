require "test_helper"

# A run on an incident starts from where its services run on the map, and from what the clues name there, within what
# the investigator may read.
class Investigation::MapFactsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    build_two_environment_map(@workspace)
    @web = map_resource(@workspace, "web")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @web)
    @incident.update!(custom_fields: { "affected_services" => [ catalog_entries(:auth_service).id ] })
    @investigation = investigation_for(@incident)
  end

  test "the resources the incident's services run on, each with what it is, what fails with it and why it is here" do
    resources = @investigation.build_seed_pack!["resources"]

    web = resources.sole
    assert_equal [ @web.id, "web", "runs Auth Service" ], web.values_at("id", "name", "why")
    assert_equal "service web on Northflank acme/shop, in Production, running", web["line"]
    assert_equal 0, web["dependents"]
    assert_equal 0, @investigation.seed_pack["resources_held_back"]
  end

  test "resources the clues name are added after the services' own, with the clue that named them" do
    source = @workspace.alert_sources.create!(name: "Grafana", provider: AlertSource::PROVIDER_GENERIC)
    source.alerts.create!(workspace: @workspace, incident: @incident, external_id: "a1", fingerprint: "pool", fields: { "service" => "orders-db" },
                          status: Alert::STATUS_FIRING, received_at: 10.minutes.ago, last_seen_at: 10.minutes.ago)

    resources = @investigation.build_seed_pack!["resources"]

    assert_equal [ "web", "orders-db" ], resources.map { |resource| resource["name"] }
    assert_equal "named in alert from Grafana, field service", resources.last["why"]
    assert_equal 1, resources.last["dependents"]
    assert_equal({ ResourceMap::KIND_SERVICE => 1 }, resources.last["dependents_by_kind"])
  end

  test "only what the investigator may read, so a name from outside its environments never reaches the pack" do
    limit_map_to(@workspace, SystemAgent.investigator, catalog_entries(:production_env))
    @investigation.update!(brief: { Investigation::Brief::KEY_NAMES => [ "secret-db", "dev-worker" ], Investigation::Brief::KEY_SOURCE => "chat" })

    pack = @investigation.build_seed_pack!

    assert_equal [ "web" ], pack["resources"].map { |resource| resource["name"] }
    resources = pack.slice("resources").to_json
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes resources, name }
  end

  test "a run whose investigator reads no map starts without resources" do
    @workspace.ability_grants.find_by!(principal: SystemAgent.investigator, action: Ability::Action.system!(Ability::Action::MAP_READ)).destroy!

    pack = @investigation.build_seed_pack!

    assert_nil pack["resources"]
    assert_nil pack["resources_held_back"]
  end

  test "changes in the day before the incident started are listed, and nothing from before or after" do
    started = Time.iso8601(Investigation::Clues.new(@investigation).gather.dig("started", "at"))
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, to_value: "abc1234def", happened_at: started - 2.hours)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_STATUS_CHANGED, from_value: "running", to_value: "failed",
                              happened_at: started - 30.hours)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_RENAMED, from_value: "www", to_value: "web", happened_at: started + 1.minute)

    changes = @investigation.build_seed_pack!["resources"].sole["changes_before_start"]

    assert_equal [ "web deployed abc1234 at #{(started - 2.hours).utc.iso8601}" ], changes
  end

  test "at most ten resources, and the pack counts the rest" do
    12.times do |index|
      resource = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE,
                                               external_id: "extra-#{index}", name: "extra-#{index.to_s.rjust(2, '0')}", integration_environment: @production_row,
                                               first_seen_at: Time.current, last_seen_at: Time.current)
      ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: resource)
    end

    pack = @investigation.build_seed_pack!

    assert_equal Investigation::MapFacts::LIMIT, pack["resources"].size
    assert_equal 3, pack["resources_held_back"]
    assert_equal "extra-00", pack["resources"].first["name"]
  end

  test "the same run always gets the same resources" do
    first = Investigation::IncidentSeed.new(@investigation).gather.except(Investigation::Seeding::KEY_GATHERED_AT)
    second = Investigation::IncidentSeed.new(@investigation).gather.except(Investigation::Seeding::KEY_GATHERED_AT)

    assert_equal first, second
    assert first["resources"].present?
  end

  private

  def investigation_for(incident)
    @workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
  end
end
