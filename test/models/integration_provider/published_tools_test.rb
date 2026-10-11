require "test_helper"

# Each hosted server's tools are held to the list its provider publishes, as test/fixtures/files/<key>_mcp_tools.txt
# copies it with where it came from: each tool as the server names it and whether it only reads or changes something.
class IntegrationProvider::PublishedToolsTest < ActiveSupport::TestCase
  PUBLISHED = %w[datadog newrelic honeycomb axiom betterstack logfire notion linear].freeze

  def published(file)
    file_fixture("#{file}_mcp_tools.txt").readlines.reject { |line| line.start_with?("#") }.to_h do |line|
      name, kind = line.split
      [ Integrations::McpExecutor.local_name(name), kind ]
    end
  end

  def reads(file) = published(file).select { |_name, kind| kind == "read" }.keys

  test "a provider counts every read its published list names, and nothing that list says changes something" do
    PUBLISHED.each do |key|
      assert_equal reads(key).sort, IntegrationProvider.find(key).read_only_tools.sort, "#{key}'s reads are the ones it publishes"
    end
  end

  test "a Jira or Confluence connection counts the reads of Jira, Confluence and Jira Service Management Operations alike" do
    atlassian = reads("atlassian")

    %w[jira confluence].each do |key|
      assert_equal atlassian.sort, IntegrationProvider.find(key).read_only_tools.sort, "#{key} reaches Atlassian's one server"
    end
    %w[searchconfluence getconfluencecontent getjsmopsalerts getjsmopsscheduleinfo].each { |tool| assert_includes atlassian, tool }
    assert_equal "change", published("atlassian").fetch("updatejsmopsalert")
  end

  test "a tool a provider's list publishes as a change is never one it counts as a read" do
    (PUBLISHED + %w[atlassian]).each do |file|
      changes = published(file).select { |_name, kind| kind == "change" }.keys
      key = file == "atlassian" ? "jira" : file
      assert_empty changes & IntegrationProvider.find(key).read_only_tools, "#{file} counts a change as a read"
    end
  end

  test "every tool a Notion or Confluence skill names is one its server publishes" do
    { "notion" => published("notion").keys, "confluence" => published("atlassian").keys }.each do |source, names|
      skills = Chat::Skill.all.select { |skill| skill.source == source }
      assert skills.any?, "#{source} has a skill"
      skills.each { |skill| skill.tools.each { |tool| assert_includes names, tool, "#{skill.name} names #{tool}" } }
    end
  end

  test "Datadog's every address asks for the toolsets its adapter and skills read" do
    adapter = Integrations::Capabilities.adapter_for("datadog")
    named = Chat::Skill.all.select { |skill| skill.source == "datadog" }.flat_map(&:tools) + adapter::TOOLS.values
    capabilities = Integrations::Capabilities::SPECS.values.map(&:tool_name)
    datadog = published("datadog").keys

    (named - capabilities).uniq.each { |tool| assert_includes datadog, tool, "Datadog's core and error-tracking toolsets have #{tool}" }
    IntegrationProvider.find("datadog").regions.each do |region|
      assert_equal "toolsets=core,error-tracking", URI.parse(region.server_url).query, "#{region.key} asks for both toolsets"
    end
  end

  test "PostHog's tools that its server marks read only but that send or stage a change are counted as changes" do
    posthog = file_fixture("posthog_mcp_tools.txt").read.split.map { |name| Integrations::McpExecutor.local_name(name) }
    entry = IntegrationProvider.find("posthog")

    assert_empty posthog.grep(/_prepare\z/) - entry.write_tools, "every -prepare tool the fixture holds is a change"
    entry.write_tools.each { |tool| assert_match(/\A(agent_feedback|.+_prepare)\z/, tool) }
    assert_not entry.reads?("agent_feedback", declared: true)
    assert entry.reads?("query_run", declared: true)
  end
end
