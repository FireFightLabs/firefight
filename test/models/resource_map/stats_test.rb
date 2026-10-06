require "test_helper"

class ResourceMap::StatsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
    @production = integration.integration_environments.create!(environment: catalog_entries(:production_env), map_swept_at: 1.hour.ago,
                                                               map_gaps: [ "Lambda functions in us-east-1 could not be read." ])
    @failing = integration.integration_environments.create!(environment: catalog_entries(:development_env), map_error: "AWS answered 403")
    integration.integration_environments.create!
    @web = make("web", status: "running", account: "111")
    @api = make("api", status: "Running", account: "222")
    @orders = make("orders", kind: ResourceMap::KIND_DATABASE, status: "failed", row: @failing)
    make("old", removed_at: 1.day.ago)
  end

  test "resources are counted by each dimension, largest first, narrowed by the query's filters" do
    assert_equal 3, stats.total
    assert_equal({ "aws" => 3 }, stats.counts(ResourceMap::Stats::BY_PROVIDER))
    assert_equal({ ResourceMap::KIND_SERVICE => 2, ResourceMap::KIND_DATABASE => 1 }, stats.counts(ResourceMap::Stats::BY_KIND))
    assert_equal({ [ "aws", "111" ] => 2, [ "aws", "222" ] => 1 }, stats.counts(ResourceMap::Stats::BY_ACCOUNT))
    assert_equal({ "Production" => 2, "Development" => 1 }, stats.counts(ResourceMap::Stats::BY_ENVIRONMENT))
    assert_equal({ "running" => 2, "failed" => 1 }, stats.counts(ResourceMap::Stats::BY_STATUS))
    assert_equal({ ResourceMap::Resource::HEALTH_OK => 2, ResourceMap::Resource::HEALTH_FAILING => 1 }, stats.counts(ResourceMap::Stats::BY_HEALTH))
    assert_equal({ ResourceMap::KIND_SERVICE => 2 }, stats(health: ResourceMap::Resource::HEALTH_OK).counts(ResourceMap::Stats::BY_KIND))
    assert_raises(ArgumentError) { stats.counts("colour") }
  end

  test "each connection's last sweep, error and gaps, the suggestions waiting on a person and the last day's changes" do
    ResourceMap::Link.suggest!(from: @web, to: @orders, relation: ResourceMap::RELATION_USES, note: "same project")
    ResourceMap::Link.suggest!(from: @api, to: @orders, relation: ResourceMap::RELATION_USES, note: "same project").confirm!(by: nil)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, happened_at: 1.hour.ago)
    @web.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, happened_at: 2.days.ago)

    connections = stats.connections.index_by(&:environment_row)
    assert_equal [ @production, @failing ].sort_by(&:id), connections.keys.sort_by(&:id)
    assert_equal [ "Lambda functions in us-east-1 could not be read." ], connections[@production].gaps
    assert_equal "AWS answered 403", connections[@failing].error
    assert_equal 1, stats.suggestions_to_review
    assert_equal({ ResourceMap::Change::KIND_DEPLOYED => 1 }, stats.recent_changes)
  end

  private

  def stats(**filters) = ResourceMap::Stats.new(@workspace, **filters)

  def make(name, kind: ResourceMap::KIND_SERVICE, status: "running", account: "111", row: @production, removed_at: nil)
    ResourceMap::Resource.create!(workspace: @workspace, provider: "aws", account: account, kind: kind, external_id: name, name: name, status: status,
                                  integration_environment: row, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago, removed_at: removed_at)
  end
end
