require "test_helper"

class Chat::MemoryTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @checkout = catalog_entries(:auth_service)
  end

  test "a chat or run starts with the memories about what it touches and the workspace wide ones, confirmed first, never disputed or rejected ones" do
    confirmed = remember("Auth Service runs on web", subject: @checkout, state: Chat::Memory::STATE_CONFIRMED)
    workspace_wide = remember("Deploys happen from main")
    remember("Something unrelated", subject: catalog_entries(:platform_team))
    remember("Auth Service uses Redis", subject: @checkout, state: Chat::Memory::STATE_REJECTED)
    remember("Auth Service is in Frankfurt", subject: @checkout, state: Chat::Memory::STATE_DISPUTED)

    assert_equal [ confirmed, workspace_wide ], Chat::Memory.starting_with(@workspace, [ @checkout ])
  end

  test "an incident touches the catalog services named on it and the resources they run on" do
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    ResourceMap.record!(integration.integration_environments.create!, ResourceMap::Snapshot.new(resources: [
      ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web")
    ]))
    web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
    ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: @checkout, resource: web)
    incident = incidents(:active_critical_ws1)
    IncidentFieldValue.create!(incident: incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: @checkout)

    assert_equal [ @checkout, web ], Chat::Memory.subjects_for(incident)
  end

  test "recall matches by subject and by any word asked, and a dispute is decided once" do
    production = remember("firefight-prod is the production database", subject: @checkout)
    remember("Deploys happen from main")

    assert_equal [ production ], Chat::Memory.recall(@workspace, query: "which PRODUCTION database")
    assert_equal [ production ], Chat::Memory.recall(@workspace, subject: @checkout)
    assert production.dispute!("The query against it found no tables")
    assert_not production.dispute!("again")
    assert_equal "The query against it found no tables", production.reload.state_reason
    assert_empty Chat::Memory.recall(@workspace, subject: @checkout)
  end

  private

  def remember(text, subject: nil, state: Chat::Memory::STATE_UNCONFIRMED)
    Chat::Memory.create!(workspace: @workspace, text: text, subject: subject, state: state)
  end
end
