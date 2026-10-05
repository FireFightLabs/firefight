require "test_helper"

# A capability finds its resource by name among what the caller reads on the map, so resource_status and the rest never
# reach a resource outside the caller's environments.
class Integrations::CapabilitiesReachTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
    @workspace.integrations.find_by!(slug: "northflank").tools.create!(name: "describe_resource", description: "Describe", read_only: true, enabled: true,
                                                                       params_schema: { "type" => "object" })
  end

  test "resource_status answers for a resource in the caller's environments and says one outside them is not on the map" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    assert_equal "web", status_of("web", @member).arguments["resource"]
    error = assert_raises(Integrations::Capabilities::Unroutable) { status_of("dev-worker", @member) }
    assert_equal "Nothing on the resource map is called dev-worker. get_resource_map lists what is there.", error.message
  end

  test "a member who reads every environment, and the investigator, reach a Development resource" do
    assert_equal "dev-worker", status_of("dev-worker", @member).arguments["resource"]
    assert_equal "dev-worker", status_of("dev-worker", SystemAgent.investigator).arguments["resource"]
  end

  test "a resource_status call over MCP from a limited member never names the resource it cannot see" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))

    response = Mcp::CapabilityToolFactory.invoke(Integrations::Capabilities::STATUS, { workspace: @workspace, principal: @member }, { resource: "secret-db" })

    assert response.error?
    assert_match "Nothing on the resource map is called secret-db", response.content.sole[:text]
  end

  private

  def status_of(name, principal) = Integrations::Capabilities.resolve(@workspace, Integrations::Capabilities::STATUS, { "resource" => name }, principal: principal)
end
