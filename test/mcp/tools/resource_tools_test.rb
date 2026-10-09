require "test_helper"

module Mcp
  module Tools
    # get_resource, get_resource_links and get_resource_neighbours on a small map. web uses orders-db, which is a branch of
    # main-db, a worker uses web, and Halon suggested web uses cache.
    class ResourceToolsTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
        @row = integration.integration_environments.create!(environment: catalog_entries(:production_env))
        @web = make("web")
        @orders = make("orders-db", kind: ResourceMap::KIND_DATABASE)
        @main = make("main-db", kind: ResourceMap::KIND_DATABASE)
        @worker = make("worker")
        @cache = make("cache", kind: ResourceMap::KIND_DATABASE)
        link(@web, @orders)
        link(@orders, @main, relation: ResourceMap::RELATION_BRANCH_OF)
        link(@worker, @web)
        link(@web, @cache, origin: ResourceMap::ORIGIN_SUGGESTED)
      end

      test "a resource is found by name, provider id or its own id, and a shared name answers with each one's id" do
        assert_equal @web.id, call(GetResource, resource: "WEB")[:id]
        assert_equal @web.id, call(GetResource, resource: @web.id)[:id]
        @web.update!(external_id: "svc-123")
        assert_equal @web.id, call(GetResource, resource: "svc-123")[:id]

        twin = make("web", account: "acme/other")
        shared = call(GetResource, resource: "web")
        assert_equal "More than one resource is called web. Name one by its id.", shared[:error]
        assert_equal [ @web.id, twin.id ].sort, shared[:candidates].map { |row| row[:id] }.sort
        assert_equal twin.id, call(GetResource, resource: twin.id)[:id]

        assert_equal ResourceMap::Resource.not_found_words("nowhere"), call(GetResource, resource: "nowhere")[:error]
        assert GetResource.perform_with_principal(workspace: @workspace, principal: @admin, args: { resource: "nowhere" }).error?
      end

      test "a present resource is chosen over a gone one of the same name" do
        @worker.update!(removed_at: 1.day.ago, name: "web")

        assert_equal @web.id, call(GetResource, resource: "web")[:id]
      end

      test "get_resource is the fact sheet without the walk, with its links counted by relation each way" do
        sheet = call(GetResource, resource: "web")

        assert_equal [ "web", ResourceMap::KIND_SERVICE, "northflank", "Production", "running", ResourceMap::Resource::HEALTH_OK, "web" ],
                     sheet.values_at(:name, :kind, :provider, :environment, :status, :health, :provider_id)
        assert_nil sheet[:links]
        assert_equal({ ResourceMap::RELATION_USES => 1 }, sheet[:links_out])
        assert_equal({ ResourceMap::RELATION_USES => 1 }, sheet[:links_in])
        assert_equal({ out: 1 }, sheet[:unconfirmed_suggestions])
      end

      test "get_resource_links lists each link with its sentence and how it was found, by direction, relation and origin" do
        every = call(GetResourceLinks, resource: "web")
        assert_equal 3, every[:total]
        assert_equal [ "web uses cache", "web uses orders-db", "worker uses web" ], every[:links].map { |link| link[:sentence] }.sort

        suggestion = every[:links].find { |link| link[:sentence] == "web uses cache" }
        assert_equal [ ResourceMap::ORIGIN_SUGGESTED, "suggested by Halon, not confirmed", false ], suggestion.values_at(:origin, :how, :confirmed)
        assert_equal({ id: @cache.id, name: "cache", kind: ResourceMap::KIND_DATABASE, provider: "northflank" }, suggestion[:other])
        declared = every[:links].find { |link| link[:sentence] == "worker uses web" }
        assert_equal [ "declared by Northflank", @worker.id ], [ declared[:how], declared[:other][:id] ]

        assert_equal [ "worker uses web" ], sentences(direction: "in")
        assert_equal [ "web uses cache", "web uses orders-db" ], sentences(direction: "out")
        assert_equal [ "web uses orders-db", "worker uses web" ], sentences(origins: "facts")
        assert_equal [ "web uses cache" ], sentences(origins: "suggestions")
        assert_equal [ "orders-db is a branch of main-db" ], call(GetResourceLinks, resource: "orders-db", relations: [ ResourceMap::RELATION_BRANCH_OF ])[:links].map { |link| link[:sentence] }
      end

      test "an inferred suggestion carries its certainty and clues" do
        ResourceMap::Link.create!(workspace: @workspace, from_resource: @worker, to_resource: @cache, relation: ResourceMap::RELATION_USES,
                                  origin: ResourceMap::ORIGIN_INFERRED, certainty: ResourceMap::CERTAINTY_LIKELY, clues: [ "Both name orders" ],
                                  last_seen_at: Time.current)

        link = call(GetResourceLinks, resource: "worker", origins: "suggestions")[:links].sole

        assert_equal [ ResourceMap::CERTAINTY_LIKELY, [ "Both name orders" ] ], link.values_at(:certainty, :clues)
        assert_equal "suggested by Firefight, likely, not confirmed: Both name orders", link[:how]
      end

      test "a link matched from a setting names the setting, never its value, in the links and the fact sheet" do
        ResourceMap::Link.find_by!(from_resource: @web, to_resource: @orders)
                         .update!(origin: ResourceMap::ORIGIN_MATCHED, integration_environment: nil, variables: [ "DATABASE_URL" ],
                                  clues: [ "DATABASE_URL on web names the address Northflank reports for orders-db" ])

        link = call(GetResourceLinks, resource: "orders-db", direction: ResourceMap::Link::DIRECTION_IN)[:links].sole
        assert_equal [ ResourceMap::ORIGIN_MATCHED, [ "DATABASE_URL" ] ], link.values_at(:origin, :settings)
        assert_equal "matched from web's DATABASE_URL setting, which names its address", link[:how]
        assert_includes call(GetResourceMap, resource: "orders-db")[:resources].sole[:links], "web uses orders-db (matched from web's DATABASE_URL setting, which names its address)"
      end

      test "links page by cursor up to the most a page holds, and a bad cursor is refused" do
        6.times { |index| link(make("caller-#{index}"), @main) }

        first = call(GetResourceLinks, resource: "main-db", limit: 4)
        second = call(GetResourceLinks, resource: "main-db", limit: 4, cursor: first[:next_cursor])

        assert_equal [ 4, 3, 7 ], [ first[:links].size, second[:links].size, first[:total] ]
        assert_nil second[:next_cursor]
        assert_equal 7, (first[:links] + second[:links]).map { |link| link[:sentence] }.uniq.size
        refused = GetResourceLinks.perform_with_principal(workspace: @workspace, principal: @admin, args: { resource: "main-db", cursor: "bad" })
        assert refused.error?
        assert_match "This cursor is not one a page gave", refused.content.sole[:text]
      end

      test "neighbours are one link away each way, grouped by relation, facts unless suggestions are asked for" do
        near = call(GetResourceNeighbours, resource: "web")

        assert_equal [ "orders-db" ], near[:depends_on][ResourceMap::RELATION_USES].map { |row| row[:name] }
        assert_equal [ "worker" ], near[:dependents][ResourceMap::RELATION_USES].map { |row| row[:name] }
        assert_equal 1, near[:depends_on][ResourceMap::RELATION_USES].sole[:dependents]
        assert_equal "1 unconfirmed suggestion left out, ask with include_suggestions to see them", near[:suggestions_left_out]

        with = call(GetResourceNeighbours, resource: "web", include_suggestions: true)
        cache = with[:depends_on][ResourceMap::RELATION_USES].find { |row| row[:name] == "cache" }
        assert cache[:unconfirmed]
        assert_nil with[:suggestions_left_out]
      end

      test "neighbours past the most shown say how many more there are" do
        stub_const(GetResourceNeighbours, :LIMIT, 2) do
          near = call(GetResourceNeighbours, resource: "web", include_suggestions: true)

          assert_equal 2, near.values_at(:depends_on, :dependents).compact.flat_map(&:values).flatten.size
          assert_equal "1 more link leads to or from web, get_resource_links pages through them", near[:more]
        end
      end

      private

      def make(name, kind: ResourceMap::KIND_SERVICE, account: "acme/shop")
        ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: account, kind: kind, external_id: name, name: name,
                                      status: "running", integration_environment: @row, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
      end

      def link(from, to, relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_DECLARED)
        ResourceMap::Link.create!(workspace: @workspace, from_resource: from, to_resource: to, relation: relation, origin: origin,
                                  integration_environment: (@row if origin == ResourceMap::ORIGIN_DECLARED), last_seen_at: Time.current)
      end

      def call(tool, **args) = tool.perform_with_principal(workspace: @workspace, principal: @admin, args: args).structured_content

      def sentences(**args) = call(GetResourceLinks, resource: "web", **args)[:links].map { |link| link[:sentence] }.sort

      def stub_const(owner, name, value)
        original = owner.const_get(name)
        owner.send(:remove_const, name)
        owner.const_set(name, value)
        yield
      ensure
        owner.send(:remove_const, name)
        owner.const_set(name, original)
      end
    end
  end
end
