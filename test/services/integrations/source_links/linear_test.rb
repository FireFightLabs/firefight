require "test_helper"

module Integrations
  module SourceLinks
    class LinearTest < ActiveSupport::TestCase
      ISSUE = { "id" => "ENG-42", "title" => "Checkout times out", "url" => "https://linear.app/acme/issue/ENG-42/checkout-times-out" }.freeze

      test "an issue read or saved links to the page Linear gives it" do
        link = Linear.new(nil).link(tool_name: "get_issue", arguments: { "id" => "ENG-42" }, text: ISSUE.to_json)

        assert_equal "Linear", link.provider
        assert_equal ISSUE["url"], link.url
        assert_equal ISSUE["url"], Linear.new(nil).link(tool_name: "save_issue", arguments: {}, text: ISSUE.to_json).url
        assert_equal Linear, Providers::Linear.source_links
      end

      test "no link for a list, an answer without an address on linear.app, or one that is not JSON" do
        assert_nil Linear.new(nil).link(tool_name: "list_issues", arguments: {}, text: ISSUE.to_json)
        assert_nil Linear.new(nil).link(tool_name: "get_issue", arguments: {}, text: ISSUE.merge("url" => "https://evil.example/x").to_json)
        assert_nil Linear.new(nil).link(tool_name: "get_issue", arguments: {}, text: "Issue ENG-42")
      end
    end
  end
end
