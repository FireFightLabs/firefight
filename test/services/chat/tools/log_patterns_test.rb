require "test_helper"

class Chat::Tools::LogPatternsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                       max_turns: 10, max_spend_cents: 400)
    northflank = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
    @row = northflank.integration_environments.create!(catalog_entry_id: catalog_entries(:production_env).id, credentials: { token: "x" }.to_json)
    @logs = northflank.tools.create!(name: "search_logs", description: "Logs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    @web = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE,
                                         external_id: "web-id", name: "web", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
  end

  test "Halon is offered new_log_patterns beside search_logs once it may read logs" do
    assert_equal Chat::Tools::STATE_NOT_GRANTED, entry.state
    grant!
    assert_equal [ Chat::Tools::STATE_READY, Chat::Tools::Groups::RESOURCES ], [ entry.state, entry.group ]
  end

  test "recent logs are read as the logs capability, mined, and answered as what is new this week and which errors are usual" do
    grant!
    ResourceMap::LogTemplate.record!(@row, @web, ResourceMap::LogMiner.mine([ "web user ada logged in", "web ERROR db timeout after 30 ms" ]), at: 1.day.ago)
    lines = [ "user zed logged in", "ERROR db timeout after 90 ms", "ERROR disk full on /var/lib" ].map do |text|
      Integrations::Telemetry::LogLine.new(at: Time.current, source: "web", text: text)
    end
    Integrations::NativeExecutor.expects(:call).with { |tool:, arguments:, **| tool == @logs && arguments == { "resource" => "web-id", "minutes" => 30, "limit" => 2_000 } }
                                .returns(Integrations::Telemetry.result(Integrations::Telemetry.logs_text(lines, asked: "web"), link: nil))

    answer = entry.tool.call("resource" => "web", "minutes" => 30)

    assert_match "Read 3 log lines of web from Northflank over the last 30 minutes. 2 usual patterns were seen in the last week.", answer
    assert_match "- [error] web ERROR disk full on /var/lib (1 line)", answer
    assert_match "so not the cause by themselves:\n- web ERROR db timeout after <NUM> ms", answer
    assert_no_match "user zed", answer
    step = @investigation.steps.find_by!(tool_name: "search_logs")
    assert_equal "northflank.search_logs", step.action_key
  end

  test "a resource not on the map is refused in words" do
    grant!
    assert_match "Nothing on the resource map is called nope", entry.tool.call("resource" => "nope")
  end

  private

  def entry = Chat::Tools.catalog(@investigation).find { |each| each.name == "new_log_patterns" }

  def grant!
    principal = @investigation.acting_principal
    Ability::Grant.create!(workspace: @workspace, principal: principal, action: @logs.reload.ability_action)
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end
end
