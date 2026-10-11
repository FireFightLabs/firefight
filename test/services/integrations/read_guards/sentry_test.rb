require "test_helper"

module Integrations
  module ReadGuards
    class SentryTest < ActiveSupport::TestCase
      # test/fixtures/files/sentry_mcp_tools.txt lists every tool the server defines and how it is reached.
      def catalog
        file_fixture("sentry_mcp_tools.txt").readlines.reject { |line| line.start_with?("#") }.to_h { |line| line.split.first(2) }
      end

      test "a call to execute_sentry_tool reads when the catalog tool it names is one the server marks read only" do
        %w[get_issue_details get_event_stacktrace get_issue_breadcrumbs get_trace_details get_release_details find_monitors].each do |name|
          assert Sentry.reads?(Sentry::TOOL, { "name" => name, "arguments" => { "issueId" => "PROJ-1" } }), "#{name} reads"
        end
        assert Sentry.reads?(Sentry::TOOL, { name: "search_issue_events" })
      end

      test "a call naming a tool that changes something, or no tool, is a change and refused while investigating" do
        %w[update_issue add_issue_note create_alert_rule delete_uptime_monitor analyze_issue_with_seer].each do |name|
          assert_not Sentry.reads?(Sentry::TOOL, { "name" => name })
        end
        assert_not Sentry.reads?(Sentry::TOOL, {})

        refusal = assert_raises(PolicyRefusal) { Sentry.reading(Sentry::TOOL, { "name" => "update_issue" }) }
        assert_equal "update_issue can change things in Sentry, so it is not used while investigating.", refusal.message
        assert_equal({ "name" => "get_issue_details" }, Sentry.reading(Sentry::TOOL, { "name" => "get_issue_details" }))
      end

      test "every read the guard knows is a tool the server defines, and none of them creates, changes or removes anything" do
        Sentry::READS.each do |name|
          assert catalog.key?(name), "the server defines no #{name}"
          assert_no_match(/\A(create|update|delete|add|remove|link|unlink|onboarding)_/, name)
        end
      end

      test "Sentry's definition names the guard, so only execute_sentry_tool passes through it" do
        assert_equal Sentry, Providers::Sentry.read_guard
        assert Sentry.guards?("execute_sentry_tool")
        assert_not Sentry.guards?("search_issues")
      end
    end
  end
end
