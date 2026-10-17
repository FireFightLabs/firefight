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

  test "a label, a comment and running CI again are safe, and a restart named by its own tool is risky" do
    label = tool(@github, "label_issue")
    tests = tool(@github, "run_tests")
    fly = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fly", name: "Fly", slug: "fly")

    assert Integrations::SafeChanges.tool?(label)
    assert Integrations::SafeChanges.tool?(tests)
    assert_equal Ability::Action::CHANGE_SAFE, label.ability_action.change_class
    assert_not Integrations::SafeChanges.tool?(tool(fly, "restart_app")), "a Fly app can be a Postgres cluster"
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
      listed = entry.safe_tools
      next if listed.empty? && entry.access_tools.empty?

      pack = Integrations::NativePack.for(entry.key)
      assert pack, "#{entry.key} lists safe or access tools, which only a native pack's own tools may be"
      changes = pack.tool_definitions.reject(&:read_only).map { |definition| definition.name.to_s }
      (listed + entry.access_tools).each { |name| assert_includes changes, name, "#{entry.key}'s #{name} is a change its pack offers" }
      entry.undo_tools.each do |name, spec|
        assert_includes listed, name, "#{entry.key} declares an undo only for a safe tool"
        assert_includes changes, spec["tool"], "#{entry.key}'s undo of #{name} is a change its pack offers"
        assert_empty [ spec["tool"] ] & (entry.access_tools + entry.mitigation_tools + entry.stopping_tools), "#{entry.key}'s undo of #{name} is plain"
      end
      assert_empty listed & (entry.access_tools + entry.mitigation_tools + entry.stopping_tools), "#{entry.key} lists a safe tool that is not plain"
    end
  end

  test "a restart through the capability is safe only on a service running more than one copy now" do
    spec = Integrations::Capabilities.spec(Integrations::Capabilities::RESTART)

    assert Integrations::SafeChanges.capability_call?(call(spec, resource!("web", instances: 3)), {})
    assert_not Integrations::SafeChanges.capability_call?(call(spec, resource!("worker", instances: 1)), {}), "a single copy goes down"
    assert_not Integrations::SafeChanges.capability_call?(call(spec, resource!("db", instances: 3, kind: ResourceMap::KIND_DATABASE)), {})
  end

  test "a scale is safe only up to double the live count and ten more, with no plan change, and a rollback never is" do
    web = resource!("web", instances: 2)
    big = resource!("api", instances: 20)
    scale = Integrations::Capabilities.spec(Integrations::Capabilities::SCALE)
    rollback = Integrations::Capabilities.spec(Integrations::Capabilities::ROLLBACK)

    assert Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 4 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 5 }), "past double"
    assert_not Integrations::SafeChanges.capability_call?(call(scale, big), { "instances" => 31 }), "more than ten more"
    assert Integrations::SafeChanges.capability_call?(call(scale, big), { "instances" => 30 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 1 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 2 })
    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 3, "plan" => "large" }), "a plan change"
    assert_not Integrations::SafeChanges.capability_call?(call(rollback, web), {})
  end

  test "a count the map read a while ago is read again first, and one that cannot be read fresh asks" do
    web = resource!("web", instances: 2, seen: 1.hour.ago)
    scale = Integrations::Capabilities.spec(Integrations::Capabilities::SCALE)
    Integrations::MapSweep.expects(:run!).with(@row).returns(false)

    assert_not Integrations::SafeChanges.capability_call?(call(scale, web), { "instances" => 3 })
  end

  private

  def resource!(name, instances:, kind: ResourceMap::KIND_SERVICE, seen: Time.current)
    @row ||= @github.integration_environments.create!(credentials: { token: "x" }.to_json)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "github", account: "acme", kind: kind, external_id: name, name: name,
                                  integration_environment: @row, first_seen_at: seen, last_seen_at: seen, details: { "instances" => instances })
  end

  def call(spec, resource)
    Integrations::Capabilities::Call.new(spec: spec, resource: resource, environment_row: @row, tool: nil, arguments: {}, present: nil, fallback: nil, keeps: nil)
  end
end
