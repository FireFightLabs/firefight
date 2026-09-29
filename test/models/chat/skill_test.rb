require "test_helper"

class Chat::SkillTest < ActiveSupport::TestCase
  test "every skill has a name of its own, says when it is used and names its tools" do
    names = Chat::Skill.all.map(&:name)

    assert names.any?
    assert_equal names.uniq, names
    Chat::Skill.all.each do |skill|
      assert skill.used_when.present?, "#{skill.name} says when it is used"
      assert skill.tools.any?, "#{skill.name} names its tools"
      assert skill.steps.present?, "#{skill.name} has steps"
    end
  end

  test "Firefight's own skills sit under the tool group they belong to" do
    groups = Chat::Tools::Groups::FIREFIGHT.map(&:key)

    Chat::Skill.all.select { |skill| skill.source == Chat::Skill::SOURCE_FIREFIGHT }.each do |skill|
      assert_includes groups, skill.domain, "#{skill.name} sits under #{skill.domain}, which is not a tool group"
    end
  end

  # A skill that names a tool or field that no longer exists would send the agent after something that is not there.
  test "every tool a skill names exists and is offered to Halon" do
    offered = Mcp::Tools.all.map { |tool_class| tool_class.name_value.to_s } - Chat::Tools::Groups::NOT_FOR_HALON

    Chat::Skill.all.each do |skill|
      skill.tools.each { |tool| assert_includes offered, tool, "#{skill.name} names #{tool}" }
    end
  end

  test "every name a skill's steps set in code is one of its tools, their parameters, a form or a form field" do
    tool_classes = Mcp::Tools.all.index_by { |tool_class| tool_class.name_value.to_s }
    known_everywhere = IncidentForm::SLUGS + IncidentSystemField.constants.grep(/\AKEY_/).map { |key| IncidentSystemField.const_get(key) }

    Chat::Skill.all.each do |skill|
      parameters = skill.tools.flat_map { |tool| tool_classes.fetch(tool).input_schema_value.to_h.fetch(:properties, {}).keys.map(&:to_s) }
      known = skill.tools + parameters + known_everywhere
      skill.steps.scan(/`([^`]+)`/).flatten.each do |name|
        assert_includes known, name, "#{skill.name} sets #{name} in code, which none of its tools, parameters or forms has"
      end
    end
  end
end
