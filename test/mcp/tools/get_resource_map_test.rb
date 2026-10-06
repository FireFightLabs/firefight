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

      test "a fact sheet lists the key checks with the read each runs, its normal, and why one cannot run, or why the kind has none" do
        web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")
        @row.integration.tools.create!(name: "query_metrics", description: "Metrics", read_only: true, enabled: true, params_schema: { "type" => "object" })
        now = Time.current
        ResourceMap::Baseline.record!(@row, [ web ], [ ResourceMap::Baseline::Found.new(key: web.key, metric: "cpu", label: "CPU", unit: "vCPU", points: [ [ now, 0.25 ] ]) ],
                                      window_from: now - 7.days, window_to: now)

        checks = call(resource: "web")[:resources].sole[:key_checks]

        assert_includes checks, "cpu (CPU): query_metrics of cpu through Northflank. Normal: usually 0.25 vCPU, 95% under 0.25 vCPU."
        assert_includes checks, "memory (Memory): query_metrics of memory through Northflank. No normal read yet."
        assert_includes checks, "latency_p95: not available here. Northflank does not keep latency_p95 for this resource. It keeps " \
                                "cpu, memory, requests, http_4xx, http_5xx, network_in, network_out, tcp_connections, disk, bandwidth."
        assert(checks.any? { |line| line.start_with?("recent_deploys: not available here.") })
        assert_equal [ ResourceMap::KeyQueries::NONE.fetch(ResourceMap::KIND_BUILD_SERVICE) ], call(resource: "builder")[:resources].sole[:key_checks]
      end

      test "a resource can be named by its id on the map, as search_map and get_resource give it" do
        web = ResourceMap::Resource.find_by!(workspace: @workspace, external_id: "web")

        assert_equal [ "web" ], call(resource: web.id)[:resources].map { |sheet| sheet[:name] }
      end

      test "a name that is not on the map says how to see what is" do
        assert_match "Leave the resource out to see the whole map", call(resource: "checkout")[:error]
      end

      test "below 300 resources every one is listed, and from 300 the map is given as its numbers, saying so and where to look" do
        fill(GetResourceMap::MAP_LINES - 4)

        listed = call
        assert_equal GetResourceMap::MAP_LINES - 1, listed[:accounts].sum { |account| account[:resources].size }
        assert_nil listed[:overview]

        fill(1, from: GetResourceMap::MAP_LINES)
        overview = call

        assert_nil overview[:accounts]
        assert_equal GetResourceMap::MAP_LINES, overview[:resources]
        assert_match "300 resources are on the map, too many to list one by one", overview[:overview]
        assert_match "find_resources searches it", overview[:overview]
        assert_equal({ "northflank" => 299, "github" => 1 }, overview[:by_provider])
        assert_equal GetResourceMap::MAP_LINES - 2, overview[:by_kind][ResourceMap::KIND_SERVICE]
        assert_equal({ GetResourceMap::NO_ENVIRONMENT => GetResourceMap::MAP_LINES }, overview[:by_environment])
        assert_equal 1, overview[:by_health][ResourceMap::Resource::HEALTH_OK]
        assert_equal %w[acme/app builder], overview[:most_depended_on].first(2).map { |row| row[:name] }.sort
        assert_equal 1, overview[:most_depended_on].first[:dependents]
        assert_equal [ "Jobs could not be read" ], overview[:connections].sole[:gaps]
      end

      private

      def fill(count, from: 0)
        now = Time.current
        ResourceMap::Resource.insert_all!(Array.new(count) do |index|
          name = "svc-#{(from + index).to_s.rjust(3, '0')}"
          { workspace_id: @workspace.id, provider: "northflank", account: "acme/shop", kind: ResourceMap::KIND_SERVICE, external_id: name, name: name,
            integration_environment_id: @row.id, first_seen_at: now, last_seen_at: now }
        end)
      end

      def found(provider, account, kind, id, status: nil)
        ResourceMap::Found.new(provider: provider, account: account, kind: kind, external_id: id, name: id, status: status, url: "https://example.test/#{id}")
      end

      def call(principal: map_reader, **args) = GetResourceMap.perform_with_principal(workspace: @workspace, principal: principal, args: args).structured_content
    end
  end
end
