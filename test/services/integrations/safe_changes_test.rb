require "test_helper"

# A change is safe only when it is harmless or put back by another tool, and touches no data, access, money or where
# production traffic goes. Everything else is risky, and the registry says which is which per tool.
class Integrations::SafeChangesTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @github = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub", slug: "github_safe")
  end

  def tool(integration, name, read_only: false)
    integration.tools.create!(name: name, description: name, enabled: true, read_only: read_only, params_schema: {})
  end

  test "a label, a comment and running CI again are safe with an undo, and a restart is safe with none" do
    label = tool(@github, "label_issue")
    tests = tool(@github, "run_tests")

    assert Integrations::SafeChanges.tool?(label)
    assert Integrations::SafeChanges.undoable?(label)
    assert Integrations::SafeChanges.tool?(tests)
    assert_not Integrations::SafeChanges.undoable?(tests)
    assert_equal Ability::Action::CHANGE_SAFE, label.ability_action.change_class
  end

  test "merging, deploying and setting a secret are risky, and a secret is an access change" do
    merge = tool(@github, "merge_pull_request")
    secret = tool(@github, "set_actions_secret")

    assert_not Integrations::SafeChanges.tool?(merge)
    assert_equal Ability::Action::CHANGE_RISKY, merge.ability_action.change_class
    assert Integrations::SafeChanges.access?(secret)
    assert_not Integrations::SafeChanges.tool?(secret)
  end

  test "a read has no change class" do
    read = tool(@github, "list_issues", read_only: true)

    assert_nil read.ability_action.change_class
    assert_not Integrations::SafeChanges.tool?(read)
  end

  test "a remote server's tool of the same name is never safe through a native provider's list" do
    gitlab = @workspace.integrations.create!(kind: Integration::KIND_MCP, provider: "gitlab", name: "GitLab", slug: "gitlab_remote",
                                             settings: { "server_url" => "https://gitlab.com/api/v4/mcp" })

    assert_not Integrations::SafeChanges.tool?(tool(gitlab, "retry_pipeline"))
  end

  test "Firefight's own reversible writes are safe, and a delete, a post or a change to who may do what is risky" do
    assert_equal Ability::Action::CHANGE_SAFE, Ability::Action.lookup("incidents.update", @workspace).change_class
    assert_equal Ability::Action::CHANGE_RISKY, Ability::Action.lookup("incidents.delete", @workspace).change_class
    assert_equal Ability::Action::CHANGE_RISKY, Ability::Action.lookup(Ability::Action::CHANNEL_POST, @workspace).change_class
    assert_equal Ability::Action::CHANGE_RISKY, Ability::Action.lookup("webhooks.create", @workspace).change_class
    assert_nil Ability::Action.lookup("incidents.read", @workspace).change_class
  end

  test "every tool a registry entry lists is a change its native pack offers, and no list overlaps another" do
    IntegrationProvider.all.each do |entry|
      listed = entry.safe_tools + entry.safe_tools_without_undo
      next if listed.empty? && entry.access_tools.empty?

      pack = Integrations::NativePack.for(entry.key)
      assert pack, "#{entry.key} lists safe or access tools, which only a native pack's own tools may be"
      changes = pack.tool_definitions.reject(&:read_only).map { |definition| definition.name.to_s }
      (listed + entry.access_tools).each { |name| assert_includes changes, name, "#{entry.key}'s #{name} is a change its pack offers" }
      assert_empty entry.safe_tools & entry.safe_tools_without_undo, "#{entry.key} lists a tool both with and without an undo"
      assert_empty listed & (entry.access_tools + entry.mitigation_tools + entry.stopping_tools), "#{entry.key} lists a safe tool that is not plain"
    end
  end

  test "a restart through the capability is safe on a service and risky on a database" do
    service = ResourceMap::Resource.new(kind: ResourceMap::KIND_SERVICE, details: {})
    database = ResourceMap::Resource.new(kind: ResourceMap::KIND_DATABASE, details: {})
    spec = Integrations::Capabilities.spec(Integrations::Capabilities::RESTART)

    assert Integrations::SafeChanges.capability_call?(call(spec, service), {})
    assert_not Integrations::SafeChanges.capability_call?(call(spec, database), {})
    assert_not Integrations::SafeChanges.capability_undoable?(call(spec, service), {})
  end

  test "a scale is safe only above the count the map last read, and a rollback never is" do
    web = ResourceMap::Resource.new(kind: ResourceMap::KIND_SERVICE, details: { "instances" => 2 })
    unknown = ResourceMap::Resource.new(kind: ResourceMap::KIND_SERVICE, details: {})
    scale = Integrations::Capabilities.spec(Integrations::Capabilities::SCALE)
    rollback = Integrations::Capabilities.spec(Integrations::Capabilities::ROLLBACK)

    assert Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 3 })
    assert Integrations::SafeChanges.capability_undoable?(call(scale, web), { "instances" => 3 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 1 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 2 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, unknown), { "instances" => 5 })
    assert_not Integrations::SafeChanges.capability_call?(call(rollback, web), {})
  end

  private

  def call(spec, resource)
    Integrations::Capabilities::Call.new(spec: spec, resource: resource, environment_row: nil, tool: nil, arguments: {}, present: nil, fallback: nil, keeps: nil)
  end
end
