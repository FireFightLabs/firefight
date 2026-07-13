require "test_helper"

class PolicyContextBuilderTest < ActiveSupport::TestCase
  fixtures :workspaces, :catalog_types, :catalog_attribute_definitions, :catalog_entries,
           :catalog_entry_relationships

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "resolves service to its owning team via relationships" do
    context = PolicyContextBuilder.build(workspace: @workspace, fields: { service: "auth_service" })

    assert_equal "auth_service", context["service"]
    assert_equal "platform_team", context["team"]
  end

  test "flattens scalar entry attributes under the field prefix" do
    context = PolicyContextBuilder.build(workspace: @workspace, fields: { service: "auth_service" })

    assert_equal "Critical", context["service.tier"]
  end

  test "does not overwrite explicitly provided fields" do
    context = PolicyContextBuilder.build(
      workspace: @workspace,
      fields: { service: "auth_service", team: "override_team" }
    )

    assert_equal "override_team", context["team"]
  end

  test "unknown slug passes fields through unchanged" do
    context = PolicyContextBuilder.build(workspace: @workspace, fields: { service: "nope", title: "x" })

    assert_equal({ "service" => "nope", "title" => "x" }, context)
  end

  test "ignores deleted entries" do
    context = PolicyContextBuilder.build(workspace: @workspace, fields: { team: "old_team" })

    assert_equal "old_team", context["team"]
    assert_nil context["team.description"]
  end

  test "normalizes non-string values" do
    context = PolicyContextBuilder.build(workspace: @workspace, fields: { severity: 1 })

    assert_equal "1", context["severity"]
  end
end
