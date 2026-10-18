require "test_helper"

module Integrations
  # Every tool a person sees on the Integrations page reads in one plain line, so a tool cannot ship with only the words
  # written for the model.
  class ToolSummariesTest < ActiveSupport::TestCase
    # The published lists of each hosted server's tools (test/fixtures/files/<file>_mcp_tools.txt), by the providers
    # that reach that server.
    PUBLISHED = { "sentry_direct" => %w[sentry], "atlassian" => %w[jira confluence] }.freeze
    DASHES = /[—–]/

    def assert_plain(summary, label)
      assert summary.present?, "#{label} has a summary"
      assert_operator summary.size, :<=, ToolSummaries::LIMIT, "#{label}'s summary fits on one line: #{summary}"
      assert summary.end_with?("."), "#{label}'s summary is a finished sentence: #{summary}"
      assert_no_match DASHES, summary, "#{label}'s summary has no dash"
      assert_not summary.include?(";"), "#{label}'s summary has no semicolon"
      assert_not summary.include?(": "), "#{label}'s summary joins nothing with a colon"
    end

    def published_names(provider_key)
      file = PUBLISHED.find { |_file, keys| keys.include?(provider_key) }&.first || provider_key
      path = Pathname(file_fixture_path).join("#{file}_mcp_tools.txt")
      return [] unless path.exist?

      path.readlines.reject { |line| line.start_with?("#") || line.blank? }.map { |line| McpExecutor.local_name(line.split.first) }
    end

    test "every tool of a native pack has a plain summary" do
      IntegrationProvider.all.each do |entry|
        NativePack.for(entry.key)&.tool_definitions&.each { |definition| assert_plain definition.summary, "#{entry.key}.#{definition.name}" }
      end
    end

    test "every tool the registry names or a server publishes has a plain summary" do
      IntegrationProvider.all.reject { |entry| entry.kind == Integration::KIND_NATIVE }.each do |entry|
        named = entry.read_only_tools + entry.write_tools + entry.safe_tools + entry.safe_until_outside_tools + entry.stopping_tools +
                entry.mitigation_tools + entry.access_tools + entry.undo_tools.keys + [ entry.code_fix_tool ].compact
        pack_tools = NativePack.for(entry.key)&.tool_definitions.to_a.map(&:name)
        (named + published_names(entry.key) - pack_tools).uniq.each { |name| assert_plain entry.tool_summaries[name], "#{entry.key}.#{name}" }
        entry.tool_summaries.each { |name, summary| assert_plain summary, "#{entry.key}.#{name}" }
      end
    end

    test "a connection's tool reads the summary its pack or registry entry gives, never its description" do
      native = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "github", name: "GitHub")
      tool = native.tools.create!(name: "list_branches", description: "Use it first. At most 100.", enabled: false)
      expected = NativePack.for("github").tool_definitions.find { |definition| definition.name == "list_branches" }.summary

      assert_equal expected, tool.summary
      assert_equal "Use it first. At most 100.", tool.description

      remote = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: "linear", name: "Linear")
      listed = remote.tools.create!(name: "list_issues", description: "Pass the team id from list_teams.", enabled: false)

      assert_equal IntegrationProvider.find("linear").tool_summaries.fetch("list_issues"), listed.summary
    end

    test "a tool neither knows shows the first sentence of its description, cut cleanly at a word" do
      assert_equal "Finds an order by its number.", ToolSummaries.first_sentence("Finds an order by its number. Use it first, e.g. for refunds.")
      assert_equal "Reads orders for a customer, e.g. a refund.", ToolSummaries.first_sentence("Reads `orders` for a **customer**, e.g. a refund.")
      assert_equal "Calls run_query for the latest rows.", ToolSummaries.first_sentence("Calls `run_query` for the _latest_ rows.")
      long = "Searches every order the shop has taken for the customer named, with the items, the totals and the address it went to"
      shown = ToolSummaries.first_sentence(long)

      assert_operator shown.size, :<=, ToolSummaries::LIMIT + 1
      assert shown.end_with?(ToolSummaries::OMISSION)
      assert long.start_with?(shown.delete_suffix(ToolSummaries::OMISSION))
      assert_nil ToolSummaries.first_sentence(nil)
      assert_nil ToolSummaries.first_sentence("  ")
    end

    test "a custom server's tool falls back to its description" do
      custom = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: "custom_mcp", name: "Ours")
      tool = custom.tools.create!(name: "lookup", description: "Looks up an order. Call it before refund.", enabled: false)

      assert_equal "Looks up an order.", tool.summary
    end
  end
end
