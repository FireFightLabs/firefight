require "test_helper"

class Chat::Tools::UseSkillTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @investigation = @workspace.investigations.create!(
      subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 10, max_spend_cents: 400
    )
    @offered = []
  end

  test "every skill travels in the tool's description with when to use it" do
    description = use_skill.description

    Chat::Skill.all.each { |skill| assert_includes description, "#{skill.name}: #{skill.used_when}" }
    assert_includes description, "firefight incident response:\ndeclaring:"
    assert_equal Chat::Skill.all.map(&:name), use_skill.parameters_schema.dig("properties", "skill", "enum")
  end

  test "loading a skill says its steps and makes the tools it names callable, and names the ones this person may not use" do
    grant_system!(Ability::Action::RESOURCE_FORMS, Ability::Action::ACTION_READ)

    answer = use_skill.call("skill" => "declaring")

    assert_includes answer, Chat::Skill.find("declaring").steps
    assert_equal [ "get_form" ], @offered.flatten.map(&:name)
    assert_includes answer, "declare_incident is not granted to whoever you are acting as"
  end

  test "a skill that does not exist is answered with the ones that do" do
    answer = use_skill.call("skill" => "juggling")

    assert_includes answer, "There is no skill called juggling"
    assert_empty @offered
  end

  private

  def use_skill = Chat::Tools::UseSkill.new(@investigation, offer: ->(tools) { @offered << tools })

  def grant_system!(resource, action)
    principal = @investigation.acting_principal
    Ability::Grant.create!(workspace: @workspace, principal: principal, action: Ability::Action.system!(Ability::Action.system_key(resource, action)))
    Ability::Resolver.bust!(principal_type: principal.class.polymorphic_name, principal_id: principal.id, workspace_id: @workspace.id)
  end
end
