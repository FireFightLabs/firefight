require "test_helper"

# What a chat's tool catalogue, its labels and its skills are read from is dated by the rows' own versions, so a write
# that moves no timestamp and leaves every count as it was still changes it.
class Workspace::ReachVersionTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake", slug: "fake")
    @environment = @fake.integration_environments.create!(credentials: { token: "x" }.to_json)
    @echo = @fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: { "type" => "object" }, enabled: true, read_only: true)
  end

  test "a tool changed with update_columns, which moves no updated_at, changes it" do
    before = @workspace.reach_version(nil)

    @echo.update_columns(read_only: false)

    assert_not_equal before, @workspace.reach_version(nil)
  end

  test "a row of each table it is read from changes it when written without a timestamp or a new row" do
    {
      "a connection" => -> { @fake.update_columns(name: "Fake again") },
      "a tool" => -> { Integration::Tool.where(id: @echo.id).update_all(enabled: false) },
      "an environment" => -> { @environment.update_columns(enabled: false) },
      "an action" => -> { @echo.ability_action.update_columns(risk_level: Ability::Action::RISK_WRITE) },
      "an ability role" => -> { @fake.permission_packs.first.update_columns(name: "Renamed pack") },
      "a custom skill" => -> { custom_skill.update_columns(enabled: false) }
    }.each do |what, write|
      custom_skill if what == "a custom skill"
      before = @workspace.reach_version(nil)
      write.call
      assert_not_equal before, @workspace.reach_version(nil), "#{what} written without a timestamp was missed"
    end
  end

  test "the principal's own row changes it, and another workspace's rows do not" do
    before = @workspace.reach_version(@member)

    @member.update_columns(role: WorkspaceMembership.roles.fetch("admin"))
    assert_not_equal before, @workspace.reach_version(@member)

    unchanged = @workspace.reach_version(nil)
    other = workspaces(:slack_workspace_two)
    other.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake", slug: "fake")
    assert_equal unchanged, @workspace.reach_version(nil)
  end

  test "is read in one query" do
    sent = []
    collect = ->(_name, _started, _finished, _id, payload) { sent << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(collect, "sql.active_record") { @workspace.reach_version(@member) }

    assert_equal 1, sent.size
  end

  private

  def custom_skill
    @custom_skill ||= Chat::CustomSkill.create_with!(workspace: @workspace, name: "game_day", by: workspace_memberships(:alice_workspace_one),
                                                      content: { "when" => "Someone asks for a game day", "tools" => [ "declare_incident" ], "steps" => "1. Declare it." })
  end
end
