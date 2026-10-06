require "test_helper"

module Mcp
  module Tools
    class ResourceMapStatsTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
        @production = integration.integration_environments.create!(environment: catalog_entries(:production_env), map_swept_at: 1.hour.ago,
                                                                   map_gaps: [ "Lambda functions could not be read" ])
        @web = make("web", status: "running")
        @api = make("api", status: "failed")
        @orders = make("orders", kind: ResourceMap::KIND_DATABASE, account: "222", status: "running")
        make("acme/web", provider: "github", kind: ResourceMap::KIND_REPOSITORY, account: "acme", status: nil, row: nil)
      end

      test "counts by each dimension, narrowed by find_resources' filters" do
        assert_equal [ { value: "aws", count: 3 }, { value: "github", count: 1 } ], call[:groups]
        assert_equal [ { value: "aws 111", count: 2 }, { value: "aws 222", count: 1 }, { value: "github acme", count: 1 } ],
                     call(group_by: ResourceMap::Stats::BY_ACCOUNT)[:groups]
        assert_equal [ { value: "Production", count: 3 }, { value: "no environment", count: 1 } ], call(group_by: ResourceMap::Stats::BY_ENVIRONMENT)[:groups]
        assert_equal [ { value: "running", count: 2 }, { value: "no status", count: 1 }, { value: "failed", count: 1 } ],
                     call(group_by: ResourceMap::Stats::BY_STATUS)[:groups]
        assert_equal [ { value: ResourceMap::Resource::HEALTH_OK, count: 2 } ],
                     call(group_by: ResourceMap::Stats::BY_HEALTH, provider: [ "aws" ], health: [ ResourceMap::Resource::HEALTH_OK ])[:groups]
        assert_equal 1, call(kind: [ ResourceMap::KIND_DATABASE ])[:resources]
        assert_equal 2, call(name_starts_with: "a")[:resources]
      end

      test "says how each connection last read the map, what waits on a person and what changed in the last day" do
        ResourceMap::Link.create!(workspace: @workspace, from_resource: @web, to_resource: @orders, relation: ResourceMap::RELATION_USES,
                                  origin: ResourceMap::ORIGIN_SUGGESTED, last_seen_at: Time.current)
        @api.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, happened_at: 1.hour.ago)
        @api.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, happened_at: 3.days.ago)

        stats = call

        assert_equal [ { connection: "AWS", environment: "Production", swept: @production.map_swept_at.iso8601, gaps: [ "Lambda functions could not be read" ] } ],
                     stats[:connections]
        assert_equal 1, stats[:suggestions_to_review]
        assert_equal({ ResourceMap::Change::KIND_DEPLOYED => 1 }, stats[:changes_last_day])
      end

      test "a team the catalog does not hold is refused" do
        refused = ResourceMapStats.perform_with_principal(workspace: @workspace, principal: @admin, args: { owner: "Nobody" })

        assert refused.error?
        assert_equal "No team called Nobody is in the catalog.", refused.content.sole[:text]
      end

      private

      def make(name, provider: "aws", kind: ResourceMap::KIND_SERVICE, account: "111", status: "running", row: @production)
        ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: account, kind: kind, external_id: name, name: name, status: status,
                                      integration_environment: row, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
      end

      def call(**args) = ResourceMapStats.perform_with_principal(workspace: @workspace, principal: @admin, args: args).structured_content
    end
  end
end
