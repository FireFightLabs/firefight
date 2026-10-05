require "test_helper"

module Integrations
  class MapSweepTest < ActiveSupport::TestCase
    setup do
      @workspace = workspaces(:slack_workspace_one)
    end

    test "the hourly schedule sweeps a connection when it is due, and Cloudflare and GitHub once a day" do
      northflank = connection("northflank", Integration::KIND_NATIVE)
      github = connection("github", Integration::KIND_NATIVE)
      cloudflare = connection("cloudflare", Integration::KIND_MCP, settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })

      assert MapSweep.due?(northflank), "never swept is due"
      northflank.update!(map_swept_at: 2.hours.ago)
      cloudflare.update!(map_swept_at: 2.hours.ago)
      github.update!(map_swept_at: 2.hours.ago)
      assert MapSweep.due?(northflank)
      assert_not MapSweep.due?(cloudflare)
      assert_not MapSweep.due?(github)

      cloudflare.update!(map_swept_at: 1.day.ago)
      github.update!(map_swept_at: 1.day.ago)
      assert MapSweep.due?(cloudflare)
      assert MapSweep.due?(github)
    end

    test "a provider says whether it is on the map, a reader backs every one that is, and one that is not says why" do
      IntegrationProvider.all.select { |provider| provider.map == IntegrationProvider::MAP_FIREFIGHT }.each do |provider|
        read = if provider.kind == Integration::KIND_MCP
          Provider.for(provider.key).map_reader.present?
        else
          NativePack.for(provider.key).instance_method(:map_of).owner != NativePack
        end
        assert read, "#{provider.key} says it is on the map and nothing reads it"
      end
      read = IntegrationProvider.all.select do |provider|
        Provider.for(provider.key).map_reader.present? || NativePack.for(provider.key)&.instance_method(:map_of)&.owner.then { |owner| owner && owner != NativePack }
      end
      assert read.all? { |provider| provider.map == IntegrationProvider::MAP_FIREFIGHT }, "a provider with a reader has to say it is on the map"
      unchecked = IntegrationProvider.all.select { |provider| provider.map == IntegrationProvider::MAP_UNCHECKED }.map(&:key)
      assert_equal %w[gitlab], unchecked, "A provider added since the rule was written lands with its reader"
      assert_raises(ArgumentError) { IntegrationProvider.declared({ "key" => "acme", "map" => "later" }, "map", IntegrationProvider::MAPS, IntegrationProvider::MAP_EXPLAINED) }
    end

    test "each call a sweep makes is in the activity log under the map sweep, with what it read and not the script" do
      row = connection("cloudflare", Integration::KIND_MCP, settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
      row.integration.tools.create!(name: MapReaders::Cloudflare::EXECUTE, description: "Call the API", params_schema: {}, enabled: true,
                                    spec: { "tool_name" => MapReaders::Cloudflare::EXECUTE })
      McpClient.any_instance.stubs(:call_tool).returns({ "content" => [ { "type" => "text", "text" => { "items" => [] }.to_json } ] })

      McpExecutor.map_of(row)

      logged = Ability::Invocation.where(workspace: @workspace, source: AbilityGateway::SOURCE_MAP_SWEEP)
      assert_equal [ "accounts" ], logged.map { |invocation| invocation.params["reads"] }
      assert_equal SystemAgent.map_sweep, logged.sole.principal
      assert_equal Ability::Invocation::OUTCOME_SUCCESS, logged.sole.outcome
      assert_not logged.sole.params.key?("code")
    end

    test "a sweep writes each status in Firefight's words, as the provider's definition maps them" do
      row = connection("northflank", Integration::KIND_NATIVE)
      Provider.stubs(:for).returns(Provider.new(key: "northflank", status_words: { "current" => "ready" }))
      found = ResourceMap::Found.new(provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: "web", name: "web", status: "current")
      NativeExecutor.stubs(:map_of).returns(ResourceMap::Snapshot.new(resources: [ found ]))

      assert MapSweep.run!(row)
      assert_equal [ "ready", ResourceMap::Resource::HEALTH_OK ], ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web").then { |web| [ web.status, web.health ] }
    end

    private

    def connection(provider, kind, settings: {})
      @workspace.integrations.create!(kind: kind, provider: provider, name: provider.humanize, slug: provider, settings: settings).integration_environments.create!
    end
  end
end
