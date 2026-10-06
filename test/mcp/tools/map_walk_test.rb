require "test_helper"

module Mcp
  module Tools
    # traverse_resource_map and blast_radius on a chain. The site is served by web, web and jobs use orders-db, orders-db is
    # a branch of main-db, which is managed in acme/infra. Halon suggested that billing uses main-db.
    class MapWalkTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        @admin = workspace_memberships(:alice_workspace_one)
        integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
        @row = integration.integration_environments.create!(environment: catalog_entries(:production_env))
        @main = make("main-db", kind: ResourceMap::KIND_DATABASE)
        @orders = make("orders-db", kind: ResourceMap::KIND_BRANCH)
        @web = make("web")
        @jobs = make("jobs", kind: ResourceMap::KIND_JOB)
        @site = make("shop.example.com", kind: ResourceMap::KIND_DOMAIN, provider: ResourceMap::DOMAINS)
        @infra = make("acme/infra", kind: ResourceMap::KIND_REPOSITORY, provider: "github")
        @billing = make("billing")
        link(@orders, @main, relation: ResourceMap::RELATION_BRANCH_OF)
        link(@web, @orders)
        link(@jobs, @orders)
        link(@site, @web, relation: ResourceMap::RELATION_SERVED_BY)
        link(@main, @infra, relation: ResourceMap::RELATION_MANAGED_BY)
        link(@billing, @main, origin: ResourceMap::ORIGIN_SUGGESTED)
      end

      test "a walk towards dependents gives each resource its hop and the link it was reached by, two links by default" do
        walk = call(TraverseResourceMap, resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS)

        assert_equal [ 2, 3 ], [ walk[:hops], walk[:reached] ]
        assert_equal [ [ "orders-db", 1, "orders-db is a branch of main-db" ], [ "jobs", 2, "jobs uses orders-db" ], [ "web", 2, "web uses orders-db" ] ],
                     walk[:resources].map { |row| row.values_at(:name, :hop, :via) }
        assert_equal @orders.id, walk[:resources].first[:id]
      end

      test "hops, kinds, relations and suggestions each change the walk, and managed_by is followed only when named" do
        assert_equal %w[orders-db jobs web shop.example.com], names(resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS, hops: 6)
        assert_equal %w[orders-db], names(resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS, hops: 0)
        assert_equal %w[shop.example.com], names(resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS, hops: 6, kinds: [ ResourceMap::KIND_DOMAIN ])
        assert_equal %w[orders-db], names(resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS, relations: [ ResourceMap::RELATION_BRANCH_OF ])
        assert_includes names(resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS, include_suggestions: true), "billing"
        assert_equal %w[web orders-db main-db], names(resource: "shop.example.com", direction: ResourceMap::Graph::DEPENDS_ON, hops: 6)
        assert_equal %w[acme/infra], names(resource: "main-db", direction: ResourceMap::Graph::DEPENDS_ON, relations: [ ResourceMap::RELATION_MANAGED_BY ])
      end

      test "a walk past the most it lists says how many more it reached" do
        stub_const(TraverseResourceMap, :LIMIT, 2) do
          walk = call(TraverseResourceMap, resource: "main-db", direction: ResourceMap::Graph::DEPENDENTS, hops: 6)

          assert_equal 2, walk[:resources].size
          assert_equal "2 more resources were reached and not listed, narrow the walk by kinds or hops", walk[:left_out]
        end
      end

      test "a direction the walk does not know is refused" do
        refused = ToolDispatcher.call(tool: TraverseResourceMap, server_context: { workspace: @workspace, principal: @admin },
                                      args: { resource: "web", direction: "sideways" })

        assert refused.error?
        assert_match "direction is one of depends_on, dependents", refused.content.sole[:text]
      end

      test "the blast radius counts what fails with a resource, names its services, owners, open incidents and top dependents" do
        ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: catalog_entries(:auth_service), resource: @web)
        incident = incidents(:active_critical_ws1)
        IncidentFieldValue.create!(incident: incident, incident_field_definition: incident_field_definitions(:affected_services_ws1),
                                   catalog_entry: catalog_entries(:auth_service))

        radius = call(BlastRadius, resource: "main-db")

        assert_equal [ 10, 4 ], radius.values_at(:hops, :dependents)
        assert_equal({ ResourceMap::KIND_BRANCH => 1, ResourceMap::KIND_DOMAIN => 1, ResourceMap::KIND_JOB => 1, ResourceMap::KIND_SERVICE => 1 }, radius[:by_kind])
        assert_equal({ "Production" => 4 }, radius[:by_environment])
        assert_equal [ "Auth Service (Service), owned by Platform Team, open incidents #{incident.identifier}" ], radius[:services]
        assert_equal [ "#{incident.identifier} #{incident.name}" ], radius[:open_incidents]
        assert_equal "orders-db", radius[:top_dependents].first[:name]
        assert_equal({ count: 1, note: "Unconfirmed suggestions, not counted in dependents. Ask with include_suggestions to list them" },
                     radius[:suggestions_would_add])
      end

      test "the blast radius follows only the hops asked for, and lists what suggestions would add only when asked" do
        assert_equal 1, call(BlastRadius, resource: "main-db", hops: 1)[:dependents]
        assert_equal 4, call(BlastRadius, resource: "main-db", hops: 50)[:dependents]

        listed = call(BlastRadius, resource: "main-db", include_suggestions: true)[:suggestions_would_add]
        assert_equal [ "billing" ], listed[:resources].map { |row| row[:name] }
      end

      private

      def make(name, kind: ResourceMap::KIND_SERVICE, provider: "northflank")
        ResourceMap::Resource.create!(workspace: @workspace, provider: provider, account: "acme", kind: kind, external_id: name, name: name,
                                      status: "running", integration_environment: @row, first_seen_at: 1.day.ago, last_seen_at: 1.hour.ago)
      end

      def link(from, to, relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_DECLARED)
        ResourceMap::Link.create!(workspace: @workspace, from_resource: from, to_resource: to, relation: relation, origin: origin, last_seen_at: Time.current)
      end

      def call(tool, **args) = tool.perform_with_principal(workspace: @workspace, principal: @admin, args: args).structured_content

      def names(**args) = call(TraverseResourceMap, **args)[:resources].map { |row| row[:name] }

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
