require "test_helper"

module Integrations
  module MapReaders
    class CloudflareTest < ActiveSupport::TestCase
      ACCOUNT = "0123456789abcdef0123456789abcdef".freeze

      # Cloudflare's answer to each fixed script, by the API path the script asks for.
      ANSWERS = {
        %r{path: "/accounts"} => { "items" => [ { "id" => ACCOUNT, "name" => "Acme" } ] },
        %r{path: "/zones"} => { "items" => [ { "id" => "z1", "name" => "firefight.app", "status" => "active", "plan.name" => "Pro" } ], "info" => { "page" => 1, "total_pages" => 1 } },
        %r{/settings/ssl} => [ { "id" => "z1", "unread" => [],
                                 "settings" => { "ssl_mode" => "strict", "certificates" => "1 active, next expiry 2026-12-01", "waf_rules" => 3,
                                                 "rate_limit_rules" => 0, "cache_rules" => 1, "page_rules" => 0, "dnssec" => "active" },
                                 "routes" => [ { "pattern" => "api.firefight.app/*", "script" => "edge-api" } ],
                                 "load_balancers" => [ { "id" => "lb1", "name" => "lb.firefight.app", "enabled" => true, "default_pools" => [ "p1" ] } ] } ],
        %r{dns_records} => { "items" => [
          { "name" => "app.firefight.app", "type" => "CNAME", "content" => "web.code.run", "proxied" => true },
          { "name" => "firefight.app", "type" => "TXT", "content" => "v=spf1" }
        ] },
        %r{workers/scripts"} => { "items" => [ { "id" => "edge-api" } ] },
        %r{/workers/scripts/" \+ encodeURIComponent} => [ { "name" => "edge-api", "bindings" => [ { "type" => "r2_bucket", "bucket_name" => "uploads" },
                                                                                                  { "type" => "queue", "queue_name" => "emails" } ] } ],
        %r{workers/domains} => { "items" => [ { "hostname" => "edge.firefight.app", "service" => "edge-api" } ] },
        %r{pages/projects} => { "items" => [ { "name" => "docs", "domains" => [ "docs.firefight.app" ], "production_branch" => "main" } ] },
        %r{r2/buckets} => { "items" => [ { "name" => "uploads", "location" => "WEUR" } ], "info" => { "cursor" => "" } },
        %r{d1/database} => { "items" => [ { "uuid" => "d1-1", "name" => "sessions" } ] },
        %r{kv/namespaces} => { "items" => [ { "id" => "kv1", "title" => "flags" } ] },
        %r{/queues"} => { "items" => [ { "queue_name" => "emails", "consumers" => [ { "script_name" => "mailer" } ] } ] },
        %r{cfd_tunnel"} => { "items" => [ { "id" => "t1", "name" => "office", "status" => "healthy" } ] },
        %r{cfd_tunnel/" \+ id} => [ { "id" => "t1", "ingress" => [ { "hostname" => "grafana.firefight.app" }, { "hostname" => nil } ] } ],
        %r{load_balancers/pools} => { "items" => [ { "id" => "p1", "name" => "origins", "enabled" => true, "origins" => [ { "address" => "web.code.run" } ] } ] },
        %r{hyperdrive/configs} => { "items" => [ { "id" => "h1", "name" => "prod-db", "origin.host" => "aws.connect.psdb.cloud", "origin.database" => "shop" } ] },
        %r{access/apps} => { "items" => [ { "id" => "a1", "name" => "Grafana", "domain" => "grafana.firefight.app" } ] }
      }.freeze

      test "zones, hostnames and everything running at the edge go on the map, linked the way requests flow" do
        snapshot = read

        names = snapshot.resources.map { |found| [ found.kind, found.name ] }
        assert_includes names, [ ResourceMap::KIND_ZONE, "firefight.app" ]
        assert_includes names, [ ResourceMap::KIND_DOMAIN, "app.firefight.app" ]
        assert_not_includes names, [ ResourceMap::KIND_DOMAIN, "web.code.run" ], "a CNAME target is linked when the map has it, never added"
        %w[edge-api docs uploads sessions flags emails prod-db office origins Grafana lb.firefight.app].each do |name|
          assert snapshot.resources.any? { |found| found.name == name }, "#{name} is on the map"
        end

        links = snapshot.links.map { |link| [ link.from.last, link.relation, link.to.last ] }
        assert_includes links, [ "app.firefight.app", ResourceMap::RELATION_PART_OF, "z1" ]
        assert_includes links, [ "app.firefight.app", ResourceMap::RELATION_SERVED_BY, "web.code.run" ]
        assert_includes links, [ "api.firefight.app", ResourceMap::RELATION_SERVED_BY, "edge-api" ]
        assert_includes links, [ "edge.firefight.app", ResourceMap::RELATION_SERVED_BY, "edge-api" ]
        assert_includes links, [ "edge-api", ResourceMap::RELATION_USES, "uploads" ]
        assert_includes links, [ "edge-api", ResourceMap::RELATION_USES, "emails" ]
        assert_includes links, [ "mailer", ResourceMap::RELATION_USES, "emails" ]
        assert_includes links, [ "docs.firefight.app", ResourceMap::RELATION_SERVED_BY, "docs" ]
        assert_includes links, [ "grafana.firefight.app", ResourceMap::RELATION_SERVED_BY, "t1" ]
        assert_includes links, [ "grafana.firefight.app", ResourceMap::RELATION_PROTECTED_BY, "a1" ]
        assert_includes links, [ "lb.firefight.app", ResourceMap::RELATION_SERVED_BY, "lb1" ]
        assert_includes links, [ "lb1", ResourceMap::RELATION_USES, "p1" ]
        assert_includes links, [ "p1", ResourceMap::RELATION_USES, "web.code.run" ]
      end

      test "a zone carries its settings, a hostname what its records say, and a hostname two sources name is one resource" do
        snapshot = read

        zone = snapshot.resources.find { |found| found.kind == ResourceMap::KIND_ZONE }
        assert_equal({ "plan" => "Pro", "ssl_mode" => "strict", "certificates" => "1 active, next expiry 2026-12-01", "waf_rules" => 3,
                       "rate_limit_rules" => 0, "cache_rules" => 1, "page_rules" => 0, "dnssec" => "active" }, zone.details)
        app = snapshot.resources.find { |found| found.name == "app.firefight.app" }
        assert_equal [ ResourceMap::DOMAINS, "firefight.app" ], [ app.provider, app.account ]
        assert_equal({ "record" => "CNAME", "points_to" => "web.code.run", "proxied" => true }, app.details)
        assert_equal 1, snapshot.resources.count { |found| found.name == "grafana.firefight.app" }
      end

      test "products the API offers that are neither read nor left out on purpose are named as not on the map yet" do
        snapshot = read(products: %w[account:workers account:billing account:gateway zone:dns_records zone:snippets])

        assert_includes snapshot.gap_texts, "Not on the map yet, by API path: account:gateway, zone:snippets."
      end

      test "with execute switched off nothing is read, and the map says why" do
        snapshot = Cloudflare.new { |_tool, _arguments| nil }.map

        assert_empty snapshot.resources
        assert_equal [ "execute is switched off for Cloudflare, so nothing it holds is on the map." ], snapshot.gap_texts
      end

      test "a list Cloudflare refuses is a gap, and being asked to slow down stops the read for today" do
        refused = read(errors: { %r{d1/database} => "Cloudflare API error: 10000: Authentication error." })
        assert_includes refused.gap_texts, "Cloudflare could not read the D1 databases: Cloudflare API error: 10000: Authentication error."
        assert_equal [ ResourceMap::KIND_DATABASE ], refused.unread_kinds

        limited = read(errors: { %r{workers/scripts"} => "Cloudflare API error: 971: Please wait and consider throttling your request speed" })
        assert_includes limited.gap_texts, "Cloudflare asked Firefight to slow down, so the rest is read on the next sweep."
        assert_not limited.resources.any? { |found| found.kind == ResourceMap::KIND_BUCKET }
        assert_equal ResourceMap::KINDS, limited.unread_kinds
      end

      test "being asked to slow down while listing the products not on the map yet stops the read with a gap, never a failed sweep" do
        limited = read(search_error: "Cloudflare API error: 971: Please wait and consider throttling your request speed")

        assert_includes limited.gap_texts, "Cloudflare asked Firefight to slow down, so the rest is read on the next sweep."
        assert_equal ResourceMap::KINDS, limited.unread_kinds
      end

      test "an answer the server cut short keeps what it holds, and those kinds are not taken as gone" do
        cut = { "items" => [ { "name" => "uploads" }, "--- TRUNCATED --- 40 more items" ], "--- TRUNCATED ---" => "info" }.to_json
        snapshot = read(raw: { %r{r2/buckets} => cut })

        assert snapshot.resources.any? { |found| found.name == "uploads" && found.kind == ResourceMap::KIND_BUCKET }
        assert_includes snapshot.unread_kinds, ResourceMap::KIND_BUCKET
        assert snapshot.gap_texts.any? { |gap| gap.start_with?("Cloudflare could not read the R2 buckets: Cloudflare's server cut the answer short") }
      end

      test "a zone setting that could not be read is a gap and holds nothing back, a Worker route list that could not is not" do
        zone = { "id" => "z1", "unread" => [ "page rules", "Worker routes" ], "error" => "Cloudflare API error: 10000: Authentication error.", "settings" => {} }
        snapshot = read(raw: { %r{/settings/ssl} => [ zone ].to_json })

        assert_includes snapshot.gap_texts, "Cloudflare could not read the page rules of firefight.app: Cloudflare API error: 10000: Authentication error."
        assert_equal [ ResourceMap::KIND_DOMAIN ], snapshot.unread_kinds
      end

      test "every product it reads, keeps as settings or leaves out is one Cloudflare's API offers" do
        offered = file_fixture("cloudflare_api_products.txt").read.split
        unknown = Cloudflare::HANDLED - offered

        assert_empty unknown, "Not in Cloudflare's API: #{unknown.join(', ')}"
        assert_equal Cloudflare::HANDLED.size, Cloudflare::HANDLED.uniq.size
      end

      test "a change to a Worker reads that Worker and its bindings alone, and one the account no longer has goes" do
        snapshot = read(scope: ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_WORKER, external_id: "edge-api"))

        assert_equal [ [ ResourceMap::KIND_WORKER, "edge-api" ] ], snapshot.resources.map { |found| [ found.kind, found.external_id ] }
        assert_equal [ [ "edge-api", "uploads" ], [ "edge-api", "emails" ] ], snapshot.links.map { |link| [ link.from.last, link.to.last ] }
        assert_empty snapshot.gone
        assert snapshot.complete?, "its bindings are replaced"

        gone = read(scope: ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_WORKER, external_id: "retired"))
        assert_equal [ [ "cloudflare", "Acme", ResourceMap::KIND_WORKER, "retired" ] ], gone.gone
        refused = read(scope: ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_WORKER, external_id: "retired"),
                       errors: { %r{workers/scripts"} => "Cloudflare API error: 10000: Authentication error." })
        assert_empty refused.gone, "a list it could not read takes nothing away"
      end

      test "a change to a zone reads that zone and its hostnames, adding links and taking none away" do
        snapshot = read(scope: ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_ZONE, external_id: "z1"))

        names = snapshot.resources.map(&:name)
        assert_equal [ "firefight.app", "app.firefight.app" ], names.first(2)
        assert_not_includes names, "edge-api"
        assert_includes snapshot.gap_texts, Cloudflare::ZONE_ONLY
        assert_not snapshot.complete?
        assert_nil read(scope: ResourceMap::Scope.new(account: "Elsewhere", kind: ResourceMap::KIND_ZONE, external_id: "z1")), "an account it cannot find is swept"
        assert_nil read(scope: ResourceMap::Scope.new(account: "Acme", kind: ResourceMap::KIND_ACCESS_APP, external_id: "a1")), "an Access app is swept"
      end

      test "the audit log's writes are read for every account in one script, and a refusal or a slow down is raised" do
        entries = [ { "account" => "Acme", "id" => "e1", "action.time" => "2026-10-06T10:00:00Z", "raw.method" => "PUT", "raw.uri" => "/client/v4/accounts/#{ACCOUNT}/workers/scripts/edge-api" } ]
        changes = reader(raw: { %r{logs/audit} => { "entries" => entries, "refused" => [], "unread" => [], "accounts" => [ "Acme" ] }.to_json })
                  .changes(since: 10.minutes.ago, before: Time.current)
        assert_equal [ entries, [], [] ], [ changes.entries, changes.refused, changes.unread ]

        cut = { "entries" => [], "refused" => [], "unread" => [], "accounts" => [ "Acme" ], "--- TRUNCATED ---" => "more" }.to_json
        assert_equal [ "Acme" ], reader(raw: { %r{logs/audit} => cut }).changes(since: 10.minutes.ago, before: Time.current).unread

        refusal = assert_raises(RemoteReader::Refused) do
          reader(errors: { %r{logs/audit} => "Cloudflare API error: 10000: Authentication error." }).changes(since: 10.minutes.ago, before: Time.current)
        end
        assert_equal "Cloudflare refused to read its audit log: Cloudflare API error: 10000: Authentication error.", refusal.message
        limited = assert_raises(Integrations::Error) do
          reader(errors: { %r{logs/audit} => "Cloudflare API error: 971: Please wait and consider throttling your request speed" }).changes(since: 10.minutes.ago, before: Time.current)
        end
        assert_kind_of RateLimited, limited
        assert_raises(Integrations::Error) { Cloudflare.new { |_tool, _arguments| nil }.changes(since: 10.minutes.ago, before: Time.current) }
      end

      private

      def read(products: [], errors: {}, raw: {}, search_error: nil, scope: nil)
        reader(products: products, errors: errors, raw: raw, search_error: search_error).then { |each| scope ? each.map(scope: scope) : each.map }
      end

      def reader(products: [], errors: {}, raw: {}, search_error: nil)
        Cloudflare.new do |tool, arguments|
          code = arguments.to_h["code"].to_s
          next { "isError" => true, "content" => [ { "type" => "text", "text" => search_error } ] } if tool == Cloudflare::SEARCH && search_error
          next text_result(products) if tool == Cloudflare::SEARCH

          given = raw.find { |pattern, _| code.match?(pattern) }
          next { "content" => [ { "type" => "text", "text" => given.last } ] } if given

          failure = errors.find { |pattern, _| code.match?(pattern) }
          next { "isError" => true, "content" => [ { "type" => "text", "text" => failure.last } ] } if failure

          answer = ANSWERS.find { |pattern, _| code.match?(pattern) }&.last
          text_result(answer || { "items" => [] })
        end
      end

      def text_result(value) = { "content" => [ { "type" => "text", "text" => value.to_json } ] }
    end
  end
end
