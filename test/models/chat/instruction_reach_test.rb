require "test_helper"

# Instructions about a resource outside someone's map reach are hidden from them wherever instructions are read.
class Chat::InstructionReachTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @entry = catalog_entries(:auth_service)
    build_two_environment_map(@workspace)
    limit_map_to(@workspace, @member, catalog_entries(:production_env))
    IncidentFieldValue.create!(incident: @incident, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: @entry)
    %w[secret-db web].each { |name| ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: @entry, resource: map_resource(@workspace, name)) }
    @hidden = write("Rotate the card tokens before touching it", map_resource(@workspace, "secret-db"))
    @shown = write("Check the session store first", map_resource(@workspace, "web"))
    @about_entry = write("Page the auth team before a rollback", @entry)
    @everywhere = handbook_page!(@workspace, "General", "Never restart the primary database").current_wording
  end

  test "a limited member's instructions leave out the hidden resource's, with its history, and keep the catalog and workspace ones" do
    @hidden = @hidden.revise!(text: "Rotate the card tokens twice", by: workspace_memberships(:alice_workspace_one))

    assert_equal [ @shown, @about_entry, @everywhere ].map(&:id).sort, Chat::Instruction.visible_to(@member, @workspace).pluck(:id).sort
    listed = Chat::Instruction.with_history(@workspace, principal: @member)
    assert_equal [ @shown, @about_entry ].map(&:id).sort, listed.map { |note, _history| note.id }.sort
    assert_no_hidden(listed.flatten.map(&:line).join("\n"))
    assert_equal 2, Chat::Instruction.visible_to(SystemAgent.investigator, @workspace).where(scope: map_resource(@workspace, "secret-db")).count
  end

  test "a chat's instructions use the asker's reach" do
    conversation = Conversation.for_mcp!(workspace: @workspace, principal: @member, incident: @incident)

    line = Conversation::Runner.new(conversation, asker: @member).send(:instructions_line)

    assert_includes line, @shown.line
    assert_includes line, @about_entry.line
    assert_no_hidden(line)
  end

  test "a run's instructions use the investigator's reach, so narrowing its grant leaves the hidden resource's out" do
    Investigation::IncidentSeed.any_instance.stubs(:gather).returns({})
    Investigation::Clues.any_instance.stubs(:gather).returns({})

    assert_includes seeded_instructions, @hidden.line

    @workspace.ability_grants.find_by!(principal: SystemAgent.investigator, action: Ability::Action.system!(Ability::Action::MAP_READ)).destroy!
    limit_map_to(@workspace, SystemAgent.investigator, catalog_entries(:production_env))

    instructions = seeded_instructions
    assert_includes instructions, @shown.line
    assert_no_hidden(instructions.join("\n"))
  end

  private

  def seeded_instructions
    run = @workspace.investigations.create!(subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400)
    run.build_seed_pack!
    instructions = run.reload.starting_facts[Investigation::Seeding::KEY_INSTRUCTIONS]
    run.update_columns(status: Investigation::STATUS_SUCCEEDED)
    instructions
  end

  def write(text, scope) = Chat::Instruction.create!(workspace: @workspace, scope: scope, text: text)

  def assert_no_hidden(text)
    assert_not_includes text, "card tokens"
    TwoEnvironmentMapHelper::HIDDEN_NAMES.each { |name| assert_not_includes text, name }
  end
end
