require "test_helper"

class Integrations::Capabilities::ConvexTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    convex = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: Integrations::Packs::Convex::PROVIDER_KEY, name: "Convex", slug: "convex")
    @row = convex.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { deploy_key: "x" }.to_json)
    Integrations::Packs::Convex.tool_definitions.each do |definition|
      convex.tools.create!(name: definition.name, description: definition.description, read_only: true, enabled: true, params_schema: definition.params_schema)
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: Integrations::Packs::Convex::PROVIDER_KEY, account: "chat", kind: ResourceMap::KIND_SERVICE,
                                  external_id: "happy-animal-123", name: "happy-animal-123", integration_environment: @row,
                                  first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "logs, errors, deploys and status of a deployment run as the pack's own tools, with only the arguments they take" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "happy-animal-123", "text" => "timeout", "exclude" => "debug", "minutes" => 30, "stream" => "app")
    assert_equal [ @row, "search_logs" ], [ logs.environment_row, logs.tool.name ]
    assert_equal({ "text" => "timeout", "exclude" => "debug", "minutes" => 30 }, logs.arguments)

    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "happy-animal-123", "text" => "OCC", "limit" => 5)
    assert_equal [ "function_errors", { "text" => "OCC", "limit" => 5 } ], [ errors.tool.name, errors.arguments ]
    assert_equal [ "recent_pushes", { "limit" => 3 } ], resolve(Integrations::Capabilities::DEPLOYS, "resource" => "happy-animal-123", "limit" => 3).then { |call| [ call.tool.name, call.arguments ] }
    assert_equal [ "deployment_status", {} ], resolve(Integrations::Capabilities::STATUS, "resource" => "happy-animal-123").then { |call| [ call.tool.name, call.arguments ] }
  end

  test "a stream Convex does not keep, a regular expression, metrics and changes are refused in words" do
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "happy-animal-123", "stream" => "build")
    assert_match "not by a regular expression", unroutable(Integrations::Capabilities::LOGS, "resource" => "happy-animal-123", "regex" => "time.*out")
    [ Integrations::Capabilities::METRICS, Integrations::Capabilities::ROLLBACK, Integrations::Capabilities::RESTART ].each do |key|
      assert_match "no connection offers", unroutable(key, "resource" => "happy-animal-123", "to" => "x")
    end
  end

  test "the capabilities wrap the pack's tools, so Halon is offered each once, and the details say what it can do" do
    adapter = Integrations::Capabilities::Convex
    assert Integrations::Packs::Convex.tool_definitions.map(&:name).all? { |name| adapter.wraps?(name) }
    assert_match "read its logs, see what was deployed, check how a resource stands, and read its errors for anything Convex runs",
                 Integrations::Capabilities.halon_sentence(Integrations::Packs::Convex::PROVIDER_KEY, "Convex")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given, principal: map_reader)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
