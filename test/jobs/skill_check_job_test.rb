require "test_helper"

class SkillCheckJobTest < ActiveJob::TestCase
  setup do
    @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale")
    @planetscale_tools = Chat::Skill.all.select { |skill| skill.source == "planetscale" }.flat_map(&:tools).uniq
  end

  test "a skill naming a tool its provider no longer offers on any connection is recorded for whoever runs Firefight" do
    offer(@planetscale_tools - [ "planetscale_get_postgres_logs" ])

    SkillCheckJob.perform_now

    problem = Chat::SkillProblem.find_by!(skill: "planetscale_query_errors")
    assert_equal "planetscale", problem.provider
    assert_equal [ "planetscale_get_postgres_logs" ], problem.missing_tools
    naming = Chat::Skill.all.select { |skill| skill.tools.include?("planetscale_get_postgres_logs") }.map(&:name)
    assert_equal naming.sort, Chat::SkillProblem.pluck(:skill).sort
  end

  test "a skill that is fixed drops out, and one whose provider nobody connected is never recorded" do
    Chat::SkillProblem.create!(skill: "planetscale_query_errors", provider: "planetscale", missing_tools: [ "gone" ], checked_at: 1.day.ago)
    offer(@planetscale_tools)

    SkillCheckJob.perform_now

    assert_equal 0, Chat::SkillProblem.count
  end

  private

  def offer(names)
    names.each { |name| @integration.tools.create!(name: name, description: name, params_schema: { "type" => "object" }) }
  end
end
