require "test_helper"

class Chat::Tools::SkillToolsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a skill of the workspace's own names the tools Halon is offered here and Halon's own reads" do
    names = Chat::Tools::SkillTools.choices(@workspace).map(&:name)

    assert_includes names, "declare_incident"
    assert_includes names, Chat::Tools::WhatChanged::NAME
    assert_nil Chat::Tools::SkillTools.problem(@workspace, %w[declare_incident check_from_outside])
    assert_equal "launch_rockets and fire are not tools Halon has in this workspace.",
                 Chat::Tools::SkillTools.problem(@workspace, %w[declare_incident launch_rockets fire])
  end

  test "a copy of a provider's skill keeps the names its library skill uses" do
    library = Chat::Skill.find("northflank_resources")

    assert_nil Chat::Tools::SkillTools.problem(@workspace, library.tools, library: library)
    assert_match "are not tools Halon has", Chat::Tools::SkillTools.problem(@workspace, library.tools)
  end
end
