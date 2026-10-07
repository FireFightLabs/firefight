require "test_helper"

module Integrations
  module MapEventSources
    class CloudflareTest < ActiveSupport::TestCase
      ACCOUNT = "0123456789abcdef0123456789abcdef".freeze

      setup do
        @workspace = workspaces(:slack_workspace_one)
        integration = Integration.create!(workspace: @workspace, kind: Integration::KIND_MCP, provider: "cloudflare", name: "Cloudflare", settings: { "server_url" => "https://mcp.cloudflare.com/mcp" })
        @row = integration.integration_environments.create!
        @reader = MapReaders::Cloudflare.new
        McpExecutor.stubs(:map_events_reader).with(@row).returns(@reader)
      end

      test "the first read starts from now, and later reads look back for entries written late" do
        @reader.expects(:changes).never
        first = Cloudflare.poll(@row, since: nil)
        assert_empty first.events

        travel 5.minutes do
          @reader.expects(:changes).with { |since:, before:| since == Time.iso8601(first.cursor) - Cloudflare::LAG && before == Time.current }
                 .returns(MapReaders::Cloudflare::Changes.new(entries: [], refused: [], unread: []))
          assert_equal Time.current.utc.iso8601, Cloudflare.poll(@row, since: first.cursor).cursor
        end
      end

      test "each write names what it changed by its API path, and a read, a data write or something not on the map names nothing" do
        events = poll(
          write("e1", "PUT", "/client/v4/accounts/#{ACCOUNT}/workers/scripts/edge-api"),
          write("e2", "DELETE", "/client/v4/accounts/#{ACCOUNT}/r2/buckets/uploads"),
          write("e3", "POST", "/client/v4/accounts/#{ACCOUNT}/queues"),
          write("e4", "PATCH", "/client/v4/zones/z1/settings/ssl"),
          write("e5", "POST", "/client/v4/zones/z1/dns_records"),
          write("e6", "PUT", "/client/v4/accounts/#{ACCOUNT}/storage/kv/namespaces/kv1/values/flag"),
          write("e7", "POST", "/client/v4/zones/z1/purge_cache"),
          write("e8", "POST", "/client/v4/accounts/#{ACCOUNT}/members"),
          write("e9", "POST", "/client/v4/accounts/#{ACCOUNT}/d1/database/d1-1/query")
        )

        assert_equal [
          [ "e1", ResourceMap::Event::UPDATED, ResourceMap::KIND_WORKER, "edge-api" ],
          [ "e2", ResourceMap::Event::REMOVED, ResourceMap::KIND_BUCKET, "uploads" ],
          [ "e3", ResourceMap::Event::ADDED, ResourceMap::KIND_QUEUE, nil ],
          [ "e4", ResourceMap::Event::UPDATED, ResourceMap::KIND_ZONE, "z1" ],
          [ "e5", ResourceMap::Event::UPDATED, ResourceMap::KIND_ZONE, "z1" ]
        ], events.map { |event| [ event.id, event.action, event.scope.kind, event.scope.external_id ] }
        assert_equal [ "Acme" ], events.map { |event| event.scope.account }.uniq
        assert_equal Time.iso8601("2026-10-06T10:00:00Z"), events.first.at
      end

      test "a write that changes which hostnames are served by what reads everything, as does an account with more than one read takes" do
        events = poll(
          write("e1", "DELETE", "/client/v4/zones/z1/dns_records/r1"),
          write("e2", "POST", "/client/v4/accounts/#{ACCOUNT}/workers/domains"),
          write("e3", "PUT", "/client/v4/accounts/#{ACCOUNT}/cfd_tunnel/t1/configurations"),
          write("e4", "PUT", "/client/v4/accounts/#{ACCOUNT}/access/apps/a1"),
          unread: [ "Acme" ]
        )

        assert_equal [ ResourceMap::Event::RESCOPE ] * 4 + [ ResourceMap::Event::RESCOPE ], events.map(&:action)
      end

      test "an account whose audit log Cloudflare refuses is refused with what reading it needs" do
        @reader.stubs(:changes).returns(MapReaders::Cloudflare::Changes.new(entries: [], refused: [ { "account" => "Acme", "error" => "Authentication error" } ], unread: []))

        refused = assert_raises(MapEventSource::Refused) { Cloudflare.poll(@row, since: 5.minutes.ago.utc.iso8601) }
        assert_equal "Cloudflare refused the audit log of Acme: Authentication error. #{Cloudflare::AUDIT_NOTE}.", refused.message

        @reader.stubs(:changes).raises(RemoteReader::Refused, "Cloudflare refused to read its audit log: forbidden.")
        assert_equal "Cloudflare refused to read its audit log: forbidden. #{Cloudflare::AUDIT_NOTE}.",
                     assert_raises(MapEventSource::Refused) { Cloudflare.poll(@row, since: 5.minutes.ago.utc.iso8601) }.message
      end

      private

      def write(id, method, uri) = { "account" => "Acme", "id" => id, "action.time" => "2026-10-06T10:00:00Z", "raw.method" => method, "raw.uri" => uri }

      def poll(*entries, unread: [])
        @reader.stubs(:changes).returns(MapReaders::Cloudflare::Changes.new(entries: entries, refused: [], unread: unread))
        Cloudflare.poll(@row, since: 5.minutes.ago.utc.iso8601).events
      end
    end
  end
end
