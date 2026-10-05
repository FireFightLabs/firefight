require "test_helper"

module Integrations
  module IssueTrackers
    class LinearTest < ActiveSupport::TestCase
      # Linear's save_issue answer as its hosted server gave it in use, trimmed to what is read.
      def answer(status_type: "backlog")
        issue = {
          "id" => "FIR-105", "title" => "Investigate automated probing against web service",
          "url" => "https://linear.app/firefight/issue/FIR-105/investigate-automated-probing-against-web-service",
          "status" => status_type == "completed" ? "Done" : "Backlog", "statusType" => status_type
        }
        { "content" => [ { "type" => "text", "text" => issue.to_json } ] }
      end

      def tracker = Linear.new

      test "an issue saved without an id is opened, with its key, title and page" do
        report = tracker.report(tool_name: "save_issue", arguments: { "team" => "FireFight", "title" => "Investigate" }, result: answer)

        assert report.opened?
        assert_equal [ "FIR-105", "Investigate automated probing against web service" ], [ report.key, report.title ]
        assert_equal "https://linear.app/firefight/issue/FIR-105/investigate-automated-probing-against-web-service", report.url
      end

      test "an issue saved with an id that is now completed or canceled is closed" do
        assert tracker.report(tool_name: "save_issue", arguments: { "id" => "FIR-105", "state" => "Done" }, result: answer(status_type: "completed")).closed?
        assert tracker.report(tool_name: "save_issue", arguments: { "id" => "FIR-105" }, result: answer(status_type: "canceled")).closed?
      end

      test "any other change, another tool, or an answer with no page reports nothing" do
        assert_nil tracker.report(tool_name: "save_issue", arguments: { "id" => "FIR-105", "priority" => 2 }, result: answer(status_type: "started"))
        assert_nil tracker.report(tool_name: "get_issue", arguments: {}, result: answer)
        assert_nil tracker.report(tool_name: "save_issue", arguments: {}, result: { "content" => [ { "type" => "text", "text" => "Created." } ] })
      end
    end
  end
end
