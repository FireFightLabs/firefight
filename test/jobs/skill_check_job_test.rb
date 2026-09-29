require "test_helper"

class SkillCheckJobTest < ActiveJob::TestCase
  setup do
    @integration = workspaces(:slack_workspace_one).integrations.create!(kind: Integration::KIND_MCP, provider: "planetscale", name: "PlanetScale")
  end

  test "a skill naming a tool its provider no longer offers on any connection is flagged" do
    offer(Chat::Skill.all.select { |skill| skill.source == "planetscale" }.flat_map(&:tools).uniq - [ "planetscale_get_postgres_logs" ])

    Rails.logger.expects(:warn).with { |line| line.include?("skill.tools_missing") && line.include?("planetscale_get_postgres_logs") }.once

    SkillCheckJob.perform_now
  end

  test "a skill whose tools are all still offered is not flagged" do
    offer(Chat::Skill.all.select { |skill| skill.source == "planetscale" }.flat_map(&:tools).uniq)

    Rails.logger.expects(:warn).with { |line| line.to_s.include?("skill.tools_missing") }.never

    SkillCheckJob.perform_now
  end

  private

  def offer(names)
    names.each { |name| @integration.tools.create!(name: name, description: name, params_schema: { "type" => "object" }) }
  end
end
