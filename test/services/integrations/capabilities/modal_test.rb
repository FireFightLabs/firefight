require "test_helper"

class Integrations::Capabilities::ModalTest < ActiveSupport::TestCase
  APP_ID = "ap-#{'a' * 22}".freeze

  setup do
    @workspace = workspaces(:slack_workspace_one)
    modal = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "modal", name: "Modal", slug: "modal")
    @row = modal.integration_environments.create!(credentials: { token_id: "ak", token_secret: "as" }.to_json)
    Integrations::Packs::Modal.tool_definitions.each do |definition|
      modal.tools.create!(name: definition.name, description: definition.description, read_only: definition.read_only, enabled: true,
                          params_schema: definition.params_schema)
    end
    ResourceMap::Resource.create!(workspace: @workspace, provider: "modal", account: "acme/main", kind: ResourceMap::KIND_SERVICE, external_id: APP_ID,
                                  name: "inference", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "each capability runs the pack tool for the app, by its id" do
    logs = resolve(Integrations::Capabilities::LOGS, "resource" => "inference", "text" => "Traceback", "exclude" => "health", "minutes" => 15, "limit" => 50)
    assert_equal [ "app_logs", { "app" => APP_ID, "text" => "Traceback", "exclude" => "health", "minutes" => 15, "limit" => 50 } ], [ logs.tool.name, logs.arguments ]
    assert_equal [ "deployment_history", { "app" => APP_ID, "limit" => 5 } ],
                 resolve(Integrations::Capabilities::DEPLOYS, "resource" => "inference", "limit" => 5).then { |call| [ call.tool.name, call.arguments ] }
    assert_equal "describe_app", resolve(Integrations::Capabilities::STATUS, "resource" => "inference").tool.name
    assert_equal({ "app" => APP_ID, "version" => "v5" }, resolve(Integrations::Capabilities::ROLLBACK, "resource" => "inference", "to" => "v5").arguments)
    assert_equal [ "rollover_app", { "app" => APP_ID } ], resolve(Integrations::Capabilities::RESTART, "resource" => "inference").then { |call| [ call.tool.name, call.arguments ] }
  end

  test "what Modal cannot answer is said, never guessed" do
    assert_match "not by a regular expression", unroutable(Integrations::Capabilities::LOGS, "resource" => "inference", "regex" => "x.*")
    assert_match "stream must be app", unroutable(Integrations::Capabilities::LOGS, "resource" => "inference", "stream" => "build")
    assert_match "no connection offers metrics", unroutable(Integrations::Capabilities::METRICS, "resource" => "inference")
    assert_match "no connection offers scaling", unroutable(Integrations::Capabilities::SCALE, "resource" => "inference", "instances" => 2)
    assert_match "Say what to roll back to", unroutable(Integrations::Capabilities::ROLLBACK, "resource" => "inference")
  end

  test "Halon is offered the capabilities in place of the tools they wrap, and keeps the log tool for its filters" do
    adapter = Integrations::Capabilities::Modal

    assert_equal %w[deployment_history describe_app rollback_app rollover_app], adapter::WRAPPED.sort
    assert_not adapter.wraps?("app_logs")
    assert_match "read its logs, see what was deployed, check how a resource stands, roll a resource back, and restart a service for anything Modal runs",
                 Integrations::Capabilities.halon_sentence("modal", "Modal")
  end

  private

  def resolve(key, given) = Integrations::Capabilities.resolve(@workspace, key, given)

  def unroutable(key, given) = assert_raises(Integrations::Capabilities::Unroutable) { resolve(key, given) }.message
end
