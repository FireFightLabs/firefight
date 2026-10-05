require "test_helper"

class Integrations::Capabilities::VercelTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @vercel = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "vercel", name: "Vercel", slug: "vercel")
    @row = @vercel.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { api_token: "x" }.to_json)
    %w[list_resources describe_resource list_deployments deployment_logs rollback_deployment promote_deployment].each do |name|
      @vercel.tools.create!(name: name, description: name, read_only: !name.end_with?("_deployment") || name == "list_deployments", enabled: true,
                            params_schema: { "type" => "object" })
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "vercel", account: "team_1", kind: ResourceMap::KIND_SITE, external_id: "prj_1",
                                  name: "shop", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "logs, deploys, status and rollback are answered by Vercel's own tools by the project's id" do
    assert_equal({ "resource" => "prj_1", "type" => "runtime", "text" => "timeout" }, resolve(Integrations::Capabilities::LOGS, "text" => "timeout", "minutes" => 30).arguments)
    assert_equal "build", resolve(Integrations::Capabilities::LOGS, "stream" => "build").arguments["type"]
    assert_equal [ "list_deployments", { "resource" => "prj_1", "limit" => 5 } ],
                 resolve(Integrations::Capabilities::DEPLOYS, "limit" => 5).then { |call| [ call.tool.name, call.arguments ] }
    assert_equal "describe_resource", resolve(Integrations::Capabilities::STATUS).tool.name
    assert_equal({ "resource" => "prj_1", "deployment" => "dpl_1" }, resolve(Integrations::Capabilities::ROLLBACK, "to" => "dpl_1").arguments)
  end

  test "what Vercel cannot answer is refused in words, and nothing it does not offer is offered" do
    assert_match "stream must be app or build", unroutable(Integrations::Capabilities::LOGS, "stream" => "requests")
    assert_match "regular expression", unroutable(Integrations::Capabilities::LOGS, "regex" => "5..")
    assert_match "no connection offers metrics", unroutable(Integrations::Capabilities::METRICS)
    assert_equal %w[logs deploys status rollback], Integrations::Capabilities::Vercel.capabilities
    assert_not Integrations::Capabilities.wrapped?(@vercel.tools.find_by!(name: "deployment_logs"))
    assert_not Integrations::Capabilities.wrapped?(@vercel.tools.find_by!(name: "promote_deployment"))
    assert Integrations::Capabilities.wrapped?(@vercel.tools.find_by!(name: "rollback_deployment"))
  end

  private

  def resolve(key, given = {}) = Integrations::Capabilities.resolve(@workspace, key, given.merge("resource" => "shop"), principal: map_reader)

  def unroutable(key, given = {})
    assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
  end
end
