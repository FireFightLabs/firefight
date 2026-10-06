require "test_helper"

module Mcp
  module Tools
    class FindResourcesTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS", slug: "aws")
        @production = integration.integration_environments.create!(environment: catalog_entries(:production_env))
        @development = integration.integration_environments.create!(environment: catalog_entries(:development_env))
      end

      test "each filter narrows to what it names, and a row says what a resource is, where it runs and how many depend on it" do
        web = make("web", details: { "engine" => "none", ResourceMap::TAGS => { "team" => "payments" } })
        orders = make("orders", account: "222", kind: ResourceMap::KIND_DATABASE, status: "FAILED", row: @development,
                                details: { "engine" => "postgres 16" })
        repo = make("acme/web", provider: "github", account: "acme", kind: ResourceMap::KIND_REPOSITORY, status: nil, row: nil)
        link(web, orders)

        assert_equal [ repo ], names(provider: [ "github" ])
        assert_equal [ orders ], names(kind: [ ResourceMap::KIND_DATABASE ])
        assert_equal [ web ], names(account: [ "111" ])
        assert_equal [ orders ], names(environment: [ "development" ])
        assert_equal [ web ], names(environment: [ "Production" ])
        assert_equal "No environment called Staging is in the catalog.", text(response(environment: [ "Staging" ]))
        assert_match "One of: development (Development), production (Production)",
                     FindResources.schema_for(@workspace).dig(:properties, :environment, :description)
        assert_equal [ orders ], names(status: [ "failed" ])
        assert_equal [ repo ], names(health: [ ResourceMap::Resource::HEALTH_UNKNOWN ])
        assert_equal [ web ], names(tag: [ "team=payments" ])
        assert_equal [ web ], names(tag: [ "team" ])
        assert_equal [ orders ], names(field: { "engine" => "postgres 16" })
        assert_equal [ orders ], names(name_starts_with: "OR")

        row = call(name_starts_with: "orders")[:resources].sole
        assert_equal({ id: orders.id, name: "orders", kind: ResourceMap::KIND_DATABASE, provider: "aws", account: "222", environment: "Development",
                       status: "FAILED", health: ResourceMap::Resource::HEALTH_FAILING, dependents: 1 }, row)
      end

      test "an owner and a catalog entry are named the way a person would, and one the catalog does not hold is refused" do
        web, api = make("web"), make("api")
        make("other")
        ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: web)
        ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:platform_team), resource: api)

        assert_equal [ api, web ], names(owner: "platform team")
        assert_equal [ api, web ], names(owner: catalog_entries(:platform_team).id)
        assert_equal [ web ], names(catalog_entry: "auth_service")
        assert_equal [ web ], names(catalog_entry: "Auth Service")

        refused = response(owner: "Auth Service")
        assert refused.error?
        assert_equal "No team called Auth Service is in the catalog.", text(refused)
        assert_match "No catalog entry called nothing", text(response(catalog_entry: "nothing"))
      end

      test "removed resources only when asked, and changed_since finds what a sweep saw change" do
        kept = make("kept")
        gone = make("gone", removed_at: 1.hour.ago)
        kept.changes_seen.create!(workspace: @workspace, kind: ResourceMap::Change::KIND_DEPLOYED, happened_at: 10.minutes.ago)

        assert_equal [ kept ], names
        assert_equal [ gone, kept ], names(include_removed: true)
        assert_equal gone.removed_at.iso8601, call(include_removed: true)[:resources].first[:gone_since]
        assert_equal [ kept ], names(changed_since: 1.hour.ago.iso8601)
        assert_match "changed_since is not a time", text(response(changed_since: "last tuesday"))
      end

      test "pages follow each other by name or by dependents, the total is given, and a bad cursor is refused clearly" do
        hub, *callers = %w[hub a b c d].map { |name| make(name) }
        callers.each { |caller| link(caller, hub) }

        first = call(limit: 2)
        second = call(limit: 2, cursor: first[:next_cursor])
        third = call(limit: 2, cursor: second[:next_cursor])
        assert_equal [ %w[a b], %w[c d], %w[hub] ], [ first, second, third ].map { |page| page[:resources].map { |row| row[:name] } }
        assert_equal "5", first[:total]
        assert_nil third[:next_cursor]

        by_dependents = call(sort: ResourceMap::Query::SORT_DEPENDENTS, limit: 1)
        assert_equal [ "hub", 4 ], by_dependents[:resources].sole.values_at(:name, :dependents)

        wrong_sort = response(cursor: by_dependents[:next_cursor])
        assert wrong_sort.error?
        assert_equal "This cursor belongs to a dependents sort. Leave it out to start from the first page.", text(wrong_sort)
        assert_equal "This cursor is not one a page gave. Leave it out to start from the first page.", text(response(cursor: "nonsense"))
      end

      test "a limit is held to its most, and past ten thousand the total says so" do
        205.times { |index| make("resource-#{index.to_s.rjust(3, '0')}") }

        assert_equal ResourceMap::Query::MAX_PAGE_SIZE, call(limit: 1_000)[:resources].size
        assert_equal ResourceMap::Query::PAGE_SIZE, call[:resources].size
        ResourceMap::Query.any_instance.stubs(:count).returns([ ResourceMap::Query::COUNT_CAP, true ])
        assert_equal "10,000+", call[:total]
      end

      private

      def make(name, provider: "aws", account: "111", kind: ResourceMap::KIND_SERVICE, status: "running", row: @production, details: {}, removed_at: nil)
        ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: account, kind: kind, external_id: name, name: name, status: status,
                                      integration_environment: row, details: details, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago, removed_at: removed_at)
      end

      def link(from, to)
        ResourceMap::Link.create!(workspace: @workspace, from_resource: from, to_resource: to, relation: ResourceMap::RELATION_USES,
                                  origin: ResourceMap::ORIGIN_DECLARED, last_seen_at: Time.current)
      end

      def response(**args) = FindResources.perform_with_principal(workspace: @workspace, principal: @admin, args: args)

      def call(**args) = response(**args).structured_content

      def names(**args)
        ids = call(**args)[:resources].map { |row| row[:id] }
        ResourceMap::Resource.where(id: ids).sort_by { |resource| ids.index(resource.id) }
      end

      def text(response) = response.content.sole[:text]
    end
  end
end
