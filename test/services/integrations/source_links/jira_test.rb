require "test_helper"

module Integrations
  module SourceLinks
    class JiraTest < ActiveSupport::TestCase
      setup do
        @links = Jira.new(nil)
      end

      test "an issue asked by its key on a site named by its address links to that issue's page" do
        link = @links.link(tool_name: "getjiraissue", arguments: { "cloudId" => "https://acme.atlassian.net", "issueIdOrKey" => "OPS-42" })

        assert_equal "Jira", link.provider
        assert_equal "https://acme.atlassian.net/browse/OPS-42", link.url
        assert_equal "https://acme.atlassian.net/browse/OPS-7",
                     @links.link(tool_name: "addoreditjiraissuecomment", arguments: { cloudId: "acme.atlassian.net/", issueIdOrKey: "OPS-7" }).url
      end

      test "a new issue links to the key Jira gave it" do
        link = @links.link(tool_name: Jira::CREATE_ISSUE, arguments: { "cloudId" => "https://acme.atlassian.net", "projectKey" => "OPS" },
                           text: %({"id":"10042","key":"OPS-43","self":"https://api.atlassian.com/ex/jira/x/rest/api/3/issue/10042"}))

        assert_equal "https://acme.atlassian.net/browse/OPS-43", link.url
      end

      test "no link when the site or the key would have to be looked up, or for a search" do
        assert_nil @links.link(tool_name: "getjiraissue", arguments: { "cloudId" => "1324a887-45db-1bf4-1e99-ef0ff456d421", "issueIdOrKey" => "OPS-42" })
        assert_nil @links.link(tool_name: "getjiraissue", arguments: { "cloudId" => "https://acme.atlassian.net", "issueIdOrKey" => "10042" })
        assert_nil @links.link(tool_name: "searchjiraissuesusingjql", arguments: { "cloudId" => "https://acme.atlassian.net", "jql" => "project = OPS" })
        assert_nil @links.link(tool_name: Jira::CREATE_ISSUE, arguments: { "cloudId" => "https://acme.atlassian.net" }, text: "Created.")
      end
    end
  end
end
