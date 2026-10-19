require "test_helper"

# The workspace's connection tools whole, read once while nothing they are read from changed and kept across requests
# as plain rows, never with a connection's environments or credentials.
class Workspace::ToolCatalogueTest < ActiveSupport::TestCase
  # Reading connection tools whole: every column of each, joined or not.
  WHOLE_READS = /AS t0_r0\b.*FROM "integration_tools"|SELECT "integration_tools"\.\* FROM "integration_tools"/

  setup do
    @workspace = workspaces(:slack_workspace_one)
    Rails.stubs(:cache).returns(ActiveSupport::Cache::MemoryStore.new)
    @fake = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "fake", name: "Fake", slug: "fake")
    @environment = @fake.integration_environments.create!(credentials: { token: "secret-token-value" }.to_json)
    @echo = @fake.tools.create!(name: "echo_text", description: "Echoes", params_schema: { "type" => "object" }, enabled: true, read_only: true)
    @write = @fake.tools.create!(name: "write_text", description: "Writes", params_schema: { "type" => "object" }, enabled: true, read_only: false)
    @off = @fake.tools.create!(name: "off_text", description: "Off", params_schema: { "type" => "object" }, enabled: false, read_only: true)
  end

  test "holds the tools the workspace switched on, with their connections, environments and actions read" do
    expected = Integration::Tool.in_workspace(@workspace).to_a
    tools = Workspace.find(@workspace.id).switched_on_tools

    assert_equal expected.map(&:id).sort, tools.map(&:id).sort
    echo = tools.find { |tool| tool.id == @echo.id }
    assert echo.association(:integration).loaded?
    assert echo.association(:ability_action).loaded?
    assert echo.integration.association(:integration_environments).loaded?
    assert_equal [ @environment.id ], echo.integration.integration_environments.map(&:id)
    assert_equal @echo.ability_action.id, echo.ability_action.id
    assert_equal @echo.params_schema, echo.params_schema
    assert_not tools.any? { |tool| tool.id == @off.id }
  end

  test "names every tool of a connection not deleted, switched on or not" do
    by_name = Workspace.find(@workspace.id).connection_tools_by_name

    assert_equal @off.id, by_name[@off.model_facing_name].id
    assert_equal @echo.id, by_name[@echo.model_facing_name].id
  end

  test "a workspace read again in another request reads no tool whole once one has" do
    Workspace.find(@workspace.id).switched_on_tools

    assert_equal 0, whole_reads { Workspace.find(@workspace.id).switched_on_tools }
  end

  test "reading them again on the same workspace reads nothing whole, however many times" do
    workspace = Workspace.find(@workspace.id)
    workspace.switched_on_tools

    assert_equal 0, whole_reads { 5.times { workspace.switched_on_tools } }
  end

  test "keeps no environment or credential in the cache" do
    Workspace.find(@workspace.id).switched_on_tools
    kept = Rails.cache.instance_variable_get(:@data).values.map { |entry| Marshal.dump(entry) }.join

    assert_not_includes kept, "secret-token-value"
    assert_not_includes kept, @environment.read_attribute_before_type_cast(:credentials).to_s
    assert_not_includes kept, @environment.id
  end

  test "a tool switched off is seen at once, however it was written" do
    workspace = Workspace.find(@workspace.id)
    workspace.switched_on_tools
    Integration::Tool.where(id: @echo.id).update_all(enabled: false)

    assert_not_includes workspace.switched_on_tools.map(&:id), @echo.id
    assert_not_includes Workspace.find(@workspace.id).switched_on_tools.map(&:id), @echo.id
  end

  test "a column written without a timestamp is seen at once" do
    Workspace.find(@workspace.id).switched_on_tools
    @echo.update_columns(description: "Echoes again")

    assert_equal "Echoes again", Workspace.find(@workspace.id).switched_on_tools.find { |tool| tool.id == @echo.id }.description
  end

  test "an action's risk written without a timestamp is seen at once" do
    Workspace.find(@workspace.id).switched_on_tools
    Ability::Action.where(id: @write.ability_action.id).update_all(reversible: true)

    assert Workspace.find(@workspace.id).switched_on_tools.find { |tool| tool.id == @write.id }.ability_action.reversible
  end

  test "a connection switched off is seen at once" do
    Workspace.find(@workspace.id).switched_on_tools
    Integration.where(id: @fake.id).update_all(disabled_at: Time.current)

    assert_empty Workspace.find(@workspace.id).switched_on_tools.select { |tool| tool.integration_id == @fake.id }
  end

  test "an environment changed is seen at once, since environments are never kept" do
    Workspace.find(@workspace.id).switched_on_tools
    @environment.update_columns(enabled: false)

    rows = Workspace.find(@workspace.id).switched_on_tools.find { |tool| tool.id == @echo.id }.integration.integration_environments
    assert_not rows.find { |row| row.id == @environment.id }.enabled?
  end

  test "a tool added is seen at once" do
    workspace = Workspace.find(@workspace.id)
    workspace.switched_on_tools
    added = @fake.tools.create!(name: "added_text", description: "Added", params_schema: { "type" => "object" }, enabled: true, read_only: true)

    assert_includes workspace.switched_on_tools.map(&:id), added.id
  end

  private

  def whole_reads(&) = queries_sent(cached: true, transactions: true, &).grep(WHOLE_READS).size
end
