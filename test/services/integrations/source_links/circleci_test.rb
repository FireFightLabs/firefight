require "test_helper"

module Integrations
  module SourceLinks
    class CircleciTest < ActiveSupport::TestCase
      setup do
        integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_MCP, provider: "circleci", name: "CircleCI",
                                          settings: { "server_url" => "https://mcp.circleci.com/v1/mcp" })
        @settings = ConnectionSettings.of(integration.integration_environments.create!)
      end

      test "a project's runs link to its pipelines page on CircleCI's site, with the vcs as CircleCI's app writes it" do
        link = Circleci.new(@settings).link(tool_name: "list_runs", arguments: { "project_slug" => "gh/acme/web", "branch" => "main" })

        assert_equal [ "CircleCI", "https://app.circleci.com/pipelines/github/acme/web" ], [ link.provider, link.url ]
        assert_equal "https://app.circleci.com/pipelines/bitbucket/acme/billing",
                     Circleci.new(@settings).link(tool_name: "list_runs", arguments: { "projectSlug" => "bb/acme/billing" }).url
        assert_equal "https://app.circleci.com/pipelines/circleci/DdaVtNusHqi24D4YT3X4eu/6EkDPZoN4ZdMKKZtBkRodt",
                     Circleci.new(@settings).link(tool_name: "list_runs", arguments: { "project_slug" => "circleci/DdaVtNusHqi24D4YT3X4eu/6EkDPZoN4ZdMKKZtBkRodt" }).url
      end

      test "a run listed by id, your own runs, another tool or a slug it cannot read get no link" do
        builder = Circleci.new(@settings)

        assert_nil builder.link(tool_name: "list_runs", arguments: {})
        assert_nil builder.link(tool_name: "list_runs", arguments: { "project_slug" => "3f1c0a52-8c1a-4f8a-9d1e-0c0a3b1f2e44" })
        assert_nil builder.link(tool_name: "list_runs", arguments: { "project_slug" => "gh/acme/web/extra" })
        assert_nil builder.link(tool_name: "list_runs", arguments: { "project_slug" => "gl/acme/web" })
        assert_nil builder.link(tool_name: "get_job_logs", arguments: { "job_id" => "x" })
      end
    end
  end
end
