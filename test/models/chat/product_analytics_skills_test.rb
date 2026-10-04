require "test_helper"

class Chat::ProductAnalyticsSkillsTest < ActiveSupport::TestCase
  # Each server's tools are held to the list its provider publishes. PostHog's comes from
  # services/mcp/schema/tool-definitions-all.json in PostHog/posthog, and Mixpanel's from the table on its MCP page.
  test "every tool a PostHog or Mixpanel skill names is one the server publishes" do
    posthog = file_fixture("posthog_mcp_tools.txt").read.split.map { |name| Integrations::McpExecutor.local_name(name) }
    mixpanel = file_fixture("mixpanel_mcp_tools.txt").read.split.map { |name| Integrations::McpExecutor.local_name(name) }

    { "posthog" => posthog, "mixpanel" => mixpanel }.each do |source, published|
      adapter = Integrations::Capabilities.adapter_for(source)
      capabilities = Integrations::Capabilities::SPECS.values.select { |spec| adapter&.const_get(:TOOLS)&.key?(spec.key) }.map(&:tool_name)
      skills = Chat::Skill.all.select { |skill| skill.source == source }
      assert skills.any?, "#{source} has skills"
      skills.each do |skill|
        skill.tools.each { |tool| assert_includes published + capabilities, tool, "#{skill.name} names #{tool}" }
      end
      adapter&.const_get(:TOOLS)&.each_value { |tool| assert_includes published, tool, "#{source}'s adapter runs #{tool}" }
    end
    IntegrationProvider.find("mixpanel").read_only_tools.each { |tool| assert_includes mixpanel, tool, "Mixpanel publishes no #{tool}" }
  end
end
