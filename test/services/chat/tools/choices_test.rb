require "test_helper"

class Chat::Tools::ChoicesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "each parameter becomes the field that holds it, and a shape a form cannot hold is kept as it is" do
    schema = {
      "properties" => {
        "query" => { "type" => "string", "description" => "Words to find" }, "limit" => { "type" => "integer" },
        "stream" => { "type" => "string", "enum" => %w[app build] }, "dry_run" => { "type" => "boolean" },
        "names" => { "type" => "array", "items" => { "type" => "string" } }, "filters" => { "type" => "object" }
      },
      "required" => [ "query" ]
    }

    fields = Chat::Tools::Choices.fields(schema).index_by(&:key)

    assert_equal %w[text number select toggle list kept], fields.values.map(&:kind)
    assert_equal [ true, "Words to find" ], [ fields["query"].required, fields["query"].description ]
    assert_equal %w[app build], fields["stream"].options
  end

  test "Firefight's own tools, the capabilities and each connection's tools are offered by the name Halon calls them, grouped as a person finds them" do
    github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github")
    github.integration_environments.create!(credentials: { token: "x" }.to_json)
    github.tools.create!(name: "ci_runs", description: "CI runs", read_only: true, enabled: true, params_schema: { "type" => "object" })
    github.tools.create!(name: "rerun_workflow", description: "Rerun", read_only: false, enabled: true,
                         params_schema: { "type" => "object", "properties" => { "run_id" => { "type" => "integer" } }, "required" => [ "run_id" ] })

    choices = Chat::Tools::Choices.tools(@workspace).index_by(&:name)

    assert_equal "Running an incident", choices.fetch(Mcp::Tools::DECLARE_INCIDENT).group
    assert_equal Chat::Tools::Choices::GROUP_RESOURCES, choices.fetch("run_history").group
    assert_equal Chat::Tools::Choices::KIND_RESOURCE, choices.fetch("run_history").fields.find { |field| field.key == "resource" }.kind
    rerun = choices.fetch("github_rerun_workflow")
    assert_equal [ "GitHub", true ], [ rerun.group, rerun.fields.find { |field| field.key == "run_id" }.required ]
    assert_not choices.key?(Mcp::Tools::ASK_HALON)
  end

  test "a watch reads with run history first, and only with reads" do
    reads = Chat::Tools::Choices.reads

    assert reads.first.history
    assert_equal Integrations::Capabilities::HISTORY, Integrations::Capabilities::SPECS.values.find { |spec| spec.tool_name == reads.first.name }.key
    assert_not_includes reads.map(&:name), "rollback"
  end
end
