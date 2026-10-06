require "test_helper"

# Halon reads the map with the reach of whoever it works for: the person in a chat, its own grant in a run.
class Conversation::MapReachTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    build_two_environment_map(@workspace)
  end

  test "in a chat Halon reads only the environments of the person who asked" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)

    answer = map_tool(Conversation::Turn.new(conversation, asker: @member)).call

    assert_match "orders-db", answer
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes answer, name }
  end

  test "a run reads the whole map through the investigator's grant, and is refused once an admin takes it away" do
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)

    assert_match "secret-db", map_tool(investigation).call

    @workspace.ability_grants.find_by!(principal: SystemAgent.investigator, action: Ability::Action.system!(Ability::Action::MAP_READ)).destroy!
    assert_match "Not allowed", map_tool(investigation).call
  end

  test "the map's other tools read with the same reach, the person's in a chat and the investigator's in a run" do
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    conversation = Conversation.start_personal!(workspace: @workspace, member: @member)
    investigation = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND,
                                                      max_turns: 10, max_spend_cents: 400)

    in_chat = map_tool(Conversation::Turn.new(conversation, asker: @member), Mcp::Tools::FindResources).call
    in_run = map_tool(investigation, Mcp::Tools::FindResources).call

    assert_match "orders-db", in_chat
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes in_chat, name }
    assert_match "secret-db", in_run
  end

  private

  def map_tool(agent_run, tool_class = Mcp::Tools::GetResourceMap)
    action = Ability::Action.lookup(Ability::Action::MAP_READ, @workspace)
    Chat::Tools::Firefight.new(agent_run, tool_class, action)
  end
end
