require "test_helper"

module Integrations
  module SourceLinks
    class ConfluenceTest < ActiveSupport::TestCase
      PAGE = { "id" => "123456", "title" => "Checkout runbook",
               "_links" => { "webui" => "/spaces/ENG/pages/123456/Checkout+runbook", "base" => "https://acme.atlassian.net/wiki" } }.freeze

      test "a page read or written links to its page in Confluence, from the page's own links" do
        link = Confluence.new(nil).link(tool_name: "getconfluencecontent", arguments: { "cloudId" => "x" }, text: PAGE.to_json)

        assert_equal "Confluence", link.provider
        assert_equal "https://acme.atlassian.net/wiki/spaces/ENG/pages/123456/Checkout+runbook", link.url
        assert_equal link.url, Confluence.new(nil).link(tool_name: "updateconfluencecontent", arguments: {}, text: PAGE.to_json).url
      end

      test "an answer without a base takes the site from a cloudId given as its address" do
        page = PAGE.merge("_links" => { "webui" => "/spaces/ENG/pages/123456" })

        assert_equal "https://acme.atlassian.net/wiki/spaces/ENG/pages/123456",
                     Confluence.new(nil).link(tool_name: "getconfluencecontent", arguments: { cloudId: "https://acme.atlassian.net" }, text: page.to_json).url
        assert_nil Confluence.new(nil).link(tool_name: "getconfluencecontent", arguments: { cloudId: "1324a887-45db" }, text: page.to_json)
      end

      test "no link for a search, an answer without the page's links, or one that is not JSON" do
        assert_nil Confluence.new(nil).link(tool_name: "searchconfluence", arguments: {}, text: PAGE.to_json)
        assert_nil Confluence.new(nil).link(tool_name: "getconfluencecontent", arguments: {}, text: { "title" => "x" }.to_json)
        assert_nil Confluence.new(nil).link(tool_name: "getconfluencecontent", arguments: {}, text: "Page body")
      end

      test "a Jira connection links a Confluence page the same way, since Atlassian's one server answers both" do
        link = Jira.new(nil).link(tool_name: "getconfluencecontent", arguments: {}, text: PAGE.to_json)

        assert_equal "Confluence", link.provider
        assert_equal Confluence, Providers::Confluence.source_links
      end
    end
  end
end
