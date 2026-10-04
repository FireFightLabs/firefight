require "test_helper"

module Mcp
  module Tools
    class GetResourceMapTest < ActiveSupport::TestCase
      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "northflank", name: "Northflank", slug: "northflank")
        @row = integration.integration_environments.create!
        web = found("northflank", "acme/shop", ResourceMap::KIND_SERVICE, "web", status: "running")
        builder = found("northflank", "acme/shop", ResourceMap::KIND_BUILD_SERVICE, "builder")
        repository = found("github", "acme", ResourceMap::KIND_REPOSITORY, "acme/app")
        ResourceMap.record!(@row, ResourceMap::Snapshot.new(
          resources: [ web, builder, repository ],
          links: [ ResourceMap::FoundLink.new(from: web.key, to: builder.key, relation: ResourceMap::RELATION_RUNS_BUILDS_OF),
                   ResourceMap::FoundLink.new(from: builder.key, to: repository.key, relation: ResourceMap::RELATION_BUILT_FROM) ],
          gaps: [ ResourceMap::Gap.new(text: "Jobs could not be read", kinds: []) ]
        ))
      end

      test "without a resource, the whole map by account, with what each connection could not read" do
        payload = call

        assert_equal [ [ "github", "acme", [ "repository, acme/app" ] ], [ "northflank", "acme/shop", [ "build_service, builder", "service, web, running" ] ] ],
                     payload[:accounts].map { |account| [ account[:provider], account[:account], account[:resources] ] }
        assert_equal [ { connection: "Northflank", swept: @row.reload.map_swept_at.iso8601, gaps: [ "Jobs could not be read" ] } ], payload[:connections]
      end

      test "a resource's fact sheet has its page and every link within two hops, saying how each was found" do
        web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
        ResourceMap::Link.create!(workspace: @workspace, from_resource: web, to_resource: ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "acme/app"),
                                  relation: ResourceMap::RELATION_USES, origin: ResourceMap::ORIGIN_SUGGESTED, last_seen_at: Time.current)

        sheet = call(resource: "WEB")[:resources].sole

        assert_equal [ "web", ResourceMap::KIND_SERVICE, "running" ], sheet.values_at(:name, :kind, :status)
        assert_equal "https://example.test/web", sheet[:page]
        assert_includes sheet[:links], "web runs builds of builder (declared by Northflank)"
        assert_includes sheet[:links], "builder is built from acme/app (declared by Northflank, two links away)"
        assert_includes sheet[:links], "web uses acme/app (suggested by Halon, not confirmed)"
      end

      test "a fact sheet says what its catalog service is for, who owns it, what people confirmed and how its incidents ended" do
        web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
        auth = catalog_entries(:auth_service)
        ResourceMap::EntryLink.create!(workspace: @workspace, catalog_entry: auth, resource: web)
        Chat::Memory.create!(workspace: @workspace, text: "web keeps sessions in Redis", subject: web, state: Chat::Memory::STATE_CONFIRMED)
        Chat::Memory.create!(workspace: @workspace, text: "web is in Frankfurt", subject: web, state: Chat::Memory::STATE_UNCONFIRMED)
        ended = incidents(:resolved_minor_ws1)
        IncidentFieldValue.create!(incident: ended, incident_field_definition: incident_field_definitions(:affected_services_ws1), catalog_entry: auth)

        sheet = call(resource: "web")[:resources].sole

        assert_equal [ "Auth Service (Service), owned by Platform Team. Handles authentication." ], sheet[:runs]
        assert_equal 1, sheet[:confirmed].size
        assert_match "web keeps sessions in Redis", sheet[:confirmed].sole
        assert_equal [ "INC-003 Image upload broken, ended #{ended.resolved_at.to_date.iso8601}: Users unable to upload profile images (from the incident summary)" ],
                     sheet[:past_incidents]
      end

      test "a fact sheet says what normal looks like for the resource's metrics" do
        web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
        now = Time.current
        ResourceMap::Baseline.record!(@row, [ web ], [ ResourceMap::Baseline::Found.new(key: web.key, metric: "cpu", label: "CPU", unit: "vCPU", points: [ [ now, 0.25 ] ]) ],
                                      window_from: now - 7.days, window_to: now)

        assert_equal [ "CPU: usually 0.25 vCPU, 95% of readings under 0.25 vCPU, peak 0.25 vCPU, over the 7 days to #{now.to_date.iso8601}" ],
                     call(resource: "web")[:resources].sole[:normal]
      end

      test "a name that is not on the map says how to see what is" do
        assert_match "Leave the resource out to see the whole map", call(resource: "checkout")[:error]
      end

      private

      def found(provider, account, kind, id, status: nil)
        ResourceMap::Found.new(provider: provider, account: account, kind: kind, external_id: id, name: id, status: status, url: "https://example.test/#{id}")
      end

      def call(**args) = GetResourceMap.perform(workspace: @workspace, args: args).structured_content
    end
  end
end
