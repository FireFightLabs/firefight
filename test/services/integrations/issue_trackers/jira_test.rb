require "test_helper"

module Integrations
  module IssueTrackers
    class JiraTest < ActiveSupport::TestCase
      def text(value) = { "content" => [ { "type" => "text", "text" => value.is_a?(String) ? value : value.to_json } ] }

      # The reads the tracker makes, answered by name, as RemoteReader hands them to its block.
      def tracker(answers = {}, tools: answers.keys)
        calls = []
        reader = Jira.new(nil, tools.index_with { |name| Struct.new(:params_schema).new({ "properties" => { "fields" => { "type" => "array" } } }) }) do |name, arguments, _reads|
          calls << [ name, arguments ]
          answers[name]
        end
        [ reader, calls ]
      end

      test "a new issue is opened with its key, the summary asked for and its page on the site the call named" do
        reader, calls = tracker
        report = reader.report(
          tool_name: "createjiraissue",
          arguments: { "cloudId" => "https://acme.atlassian.net", "projectKey" => "OPS", "summary" => "Restrict the origin to Cloudflare" },
          result: text({ "id" => "10001", "key" => "OPS-42", "self" => "https://api.atlassian.com/ex/jira/abc/rest/api/3/issue/10001" })
        )

        assert report.opened?
        assert_equal [ "OPS-42", "Restrict the origin to Cloudflare", "https://acme.atlassian.net/browse/OPS-42" ], [ report.key, report.title, report.url ]
        assert_empty calls
      end

      test "a cloud id given as an id is placed on its site by the resources Atlassian lists" do
        reader, = tracker({ "getaccessibleatlassianresources" => text([ { "id" => "abc-123", "url" => "https://acme.atlassian.net" } ]) })

        report = reader.report(tool_name: "createjiraissue", arguments: { "cloudId" => "abc-123", "summary" => "Fix" }, result: text({ "key" => "OPS-7" }))

        assert_equal "https://acme.atlassian.net/browse/OPS-7", report.url
      end

      test "a transition closes the issue only when Firefight's own read finds it in the done category" do
        done = { "fields" => { "summary" => "Restrict the origin", "status" => { "name" => "Closed", "statusCategory" => { "key" => "done" } } } }
        reader, calls = tracker({ "getjiraissue" => text(done) })

        report = reader.report(tool_name: "transitionjiraissue", arguments: { "cloudId" => "acme.atlassian.net", "issueIdOrKey" => "OPS-42", "transition" => { "id" => "31" } }, result: text("Transitioned."))

        assert report.closed?
        assert_equal [ "OPS-42", "Restrict the origin", "https://acme.atlassian.net/browse/OPS-42" ], [ report.key, report.title, report.url ]
        assert_equal [ [ "getjiraissue", { "cloudId" => "acme.atlassian.net", "issueIdOrKey" => "OPS-42", "fields" => %w[summary status] } ] ], calls
      end

      test "a transition elsewhere, or one whose issue cannot be read, closes nothing" do
        moving = { "fields" => { "status" => { "statusCategory" => { "key" => "indeterminate" } } } }
        reader, = tracker({ "getjiraissue" => text(moving) })
        arguments = { "cloudId" => "acme.atlassian.net", "issueIdOrKey" => "OPS-42" }

        assert_nil reader.report(tool_name: "transitionjiraissue", arguments: arguments, result: text("ok"))
        assert_nil tracker({}, tools: []).first.report(tool_name: "transitionjiraissue", arguments: arguments, result: text("ok"))
      end
    end
  end
end
