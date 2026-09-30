module Integrations
  module MapReaders
    # Cloudflare on the resource map, read through Cloudflare's own server with a fixed script Firefight wrote, never
    # one a model wrote. Only execute reaches the account, so the connection has to allow it, and it reads nothing but
    # lists. Things that run or hold data are resources: zones, hostnames, Workers, Pages, R2, D1, KV, Queues,
    # Hyperdrive, Tunnels, load balancers and their pools, and Access applications. A zone's rules, certificates and
    # SSL mode are read into its details, so a change to them is recorded. Logs, analytics, billing and Cloudflare's
    # own catalogs are left out on purpose, and every other product the API offers is named as not on the map yet.
    class Cloudflare
      PROVIDER = "cloudflare".freeze
      EXECUTE = "execute".freeze
      SEARCH = "search".freeze
      # Cloudflare changes slowly next to a deploy, so it is read once a day, and on Sync now.
      EVERY = 1.day
      MAX_PAGES = 20
      PER_PAGE = 100
      CHUNK = 20
      DASHBOARD = "https://dash.cloudflare.com".freeze
      TRUNCATED = "--- TRUNCATED ---".freeze
      RATE_LIMITED = /\b429\b|rate limit/i
      HOSTNAME_RECORDS = %w[A AAAA CNAME].freeze

      # The API's products by the path segment after /accounts/<id> or /zones/<id>, as Cloudflare's spec names them.
      READ = %w[
        account:access account:cfd_tunnel account:d1 account:hyperdrive account:load_balancers account:pages account:queues
        account:r2 account:storage account:tunnels account:workers zone:dns_records zone:load_balancers zone:workers
      ].freeze
      SETTINGS = %w[zone:dnssec zone:pagerules zone:rulesets zone:settings zone:ssl].freeze
      LEFT_OUT = {
        "logs and analytics" => %w[
          account:analytics_engine account:audit_logs account:billable account:billable-usage account:logpush account:logs
          account:media account:pcaps account:reporting account:rum zone:analytics zone:dns_analytics zone:logpush zone:logs
          zone:media zone:rate_limit_analytics zone:speed_api zone:stream
        ],
        "billing and account administration" => %w[
          account:billing account:entitlements account:iam account:members account:oauth_clients account:organizations
          account:payment-methods account:profile account:receipts account:roles account:scim account:settings account:shares
          account:sso_connectors account:subscriptions account:tags account:tokens zone:available_plans zone:available_rate_plans
          zone:entitlements zone:hold zone:subscription zone:tags
        ],
        "Cloudflare's own lookups and catalogs" => %w[
          account:abuse-reports account:botnet_feed account:brand-protection account:cloudforce-one account:intel
          account:registrar-sandbox account:resource-library account:urlscanner zone:intel
        ]
      }.freeze
      HANDLED = (READ + SETTINGS + LEFT_OUT.values.flatten).freeze

      PICK = "const pick = (x, fields) => Object.fromEntries(fields.map((f) => [f, f.split(\".\").reduce((v, k) => v == null ? v : v[k], x)]));".freeze

      # Every product the live spec offers at account or zone level, as "account:<segment>" or "zone:<segment>".
      PRODUCTS_SCRIPT = <<~JS.freeze
        async () => {
          const found = new Set();
          for (const [path, methods] of Object.entries(spec.paths)) {
            const match = path.match(/^\\/(accounts|zones)\\/\\{[^}]+\\}\\/([^/]+)/);
            if (match && methods.get) found.add((match[1] === "accounts" ? "account:" : "zone:") + match[2]);
          }
          return [...found].sort();
        }
      JS

      Stop = Class.new(StandardError)

      # call_tool runs one of the connection's tools by its name and answers what it returned, or nil when the admin has
      # it switched off.
      def initialize(&call_tool)
        @call_tool = call_tool
        @resources = []
        @links = []
        @gaps = []
        @served = []
        @switched_off = []
      end

      def map
        begin
          listed = accounts
          if @switched_off.include?(EXECUTE)
            return ResourceMap::Snapshot.new(resources: [], gaps: [ "execute is switched off for Cloudflare, so nothing it holds is on the map." ])
          end

          listed.each { |account| read_account(account) }
        rescue Stop
          @gaps << "Cloudflare asked Firefight to slow down, so the rest is read on the next sweep."
        end
        @gaps << not_yet
        ResourceMap::Snapshot.new(resources: resources, links: @links.uniq, gaps: @gaps.compact.uniq)
      end

      private

      # A hostname only served, with no DNS record of its own in these zones, is still added, with nothing else known.
      def resources
        known = @resources.map(&:key)
        extra = @served.uniq.map { |host| ResourceMap.domain(host) }.reject { |found| known.include?(found.key) }
        (@resources + extra).uniq(&:key)
      end

      def accounts
        Array(run("accounts", list_script("/accounts", { per_page: 50 }, %w[id name]))&.dig("items"))
      end

      def read_account(account)
        @account = account
        zones = pages("zones", "/zones", { "account.id" => account["id"] }, %w[id name status plan.name])
        zones.each { |zone| read_zone(zone) }
        read_workers
        read_pages
        read_storage
        read_tunnels
        read_pools
        read_hyperdrive
        read_access
      end

      def read_zone(zone)
        settings = run("the settings of #{zone['name']}", settings_script(zone["id"])) || {}
        add(ResourceMap::KIND_ZONE, zone["id"], zone["name"], status: zone["status"], url: dashboard(zone["name"]),
                                                                details: { "plan" => zone["plan.name"] }.merge(settings.compact))
        records = pages("DNS records of #{zone['name']}", "/zones/#{zone['id']}/dns_records", {}, %w[name type content proxied])
        records.select { |record| HOSTNAME_RECORDS.include?(record["type"]) }.group_by { |record| record["name"] }.each do |host, found|
          hostname(host, zone, found)
        end
        routes = pages("Worker routes of #{zone['name']}", "/zones/#{zone['id']}/workers/routes", {}, %w[pattern script])
        routes.each { |route| serve(host_of(route["pattern"]), key(ResourceMap::KIND_WORKER, route["script"])) if route["script"] }
        balancers = pages("load balancers of #{zone['name']}", "/zones/#{zone['id']}/load_balancers", {}, %w[id name enabled default_pools fallback_pool])
        balancers.each { |balancer| load_balancer(balancer) }
      end

      def hostname(host, zone, records)
        found = ResourceMap.domain(host)
        @resources << found.with(details: {
          "record" => records.map { |record| record["type"] }.uniq.join(", "), "points_to" => records.map { |record| record["content"] }.join(", "),
          "proxied" => records.any? { |record| record["proxied"] }
        })
        link(found.key, key(ResourceMap::KIND_ZONE, zone["id"]), ResourceMap::RELATION_PART_OF)
        records.select { |record| record["type"] == "CNAME" }.each { |record| link(found.key, ResourceMap.domain(record["content"]).key, ResourceMap::RELATION_SERVED_BY) }
      end

      def load_balancer(balancer)
        found = add(ResourceMap::KIND_LOAD_BALANCER, balancer["id"], balancer["name"], status: (balancer["enabled"] == false ? "disabled" : "active"))
        serve(balancer["name"], found)
        (Array(balancer["default_pools"]) + [ balancer["fallback_pool"] ]).compact.uniq.each do |pool|
          link(found, key(ResourceMap::KIND_ORIGIN_POOL, pool), ResourceMap::RELATION_USES)
        end
      end

      def read_workers
        workers = Array(run("Workers", list_script("/accounts/#{@account['id']}/workers/scripts", {}, %w[id]))&.dig("items"))
        workers.each { |worker| add(ResourceMap::KIND_WORKER, worker["id"], worker["id"], url: dashboard("workers-and-pages")) }
        workers.map { |worker| worker["id"] }.each_slice(CHUNK) do |names|
          Array(run("Worker bindings", bindings_script(names))).each { |settings| bindings(settings) }
        end
        domains = pages("Worker custom domains", "/accounts/#{@account['id']}/workers/domains", {}, %w[hostname service])
        domains.each { |domain| serve(domain["hostname"], key(ResourceMap::KIND_WORKER, domain["service"])) if domain["service"] }
      end

      def bindings(settings)
        return @gaps << "The bindings of Worker #{settings['name']} could not be read: #{settings['error']}" if settings["error"]

        worker = key(ResourceMap::KIND_WORKER, settings["name"])
        Array(settings["bindings"]).each do |binding|
          target = case binding["type"]
          when "r2_bucket" then key(ResourceMap::KIND_BUCKET, binding["bucket_name"])
          when "d1" then key(ResourceMap::KIND_DATABASE, binding["id"] || binding["database_id"])
          when "kv_namespace" then key(ResourceMap::KIND_KV_NAMESPACE, binding["namespace_id"])
          when "queue" then key(ResourceMap::KIND_QUEUE, binding["queue_name"])
          when "hyperdrive" then key(ResourceMap::KIND_DATABASE_PROXY, binding["id"])
          when "service" then key(ResourceMap::KIND_WORKER, binding["service"])
          end
          link(worker, target, ResourceMap::RELATION_USES) if target&.last.present?
        end
      end

      def read_pages
        projects = pages("Pages projects", "/accounts/#{@account['id']}/pages/projects", {}, %w[name subdomain domains production_branch], per_page: 10)
        projects.each do |project|
          found = add(ResourceMap::KIND_SITE, project["name"], project["name"], url: dashboard("workers-and-pages"),
                                                                                  details: { "branch" => project["production_branch"] }.compact)
          Array(project["domains"]).each { |domain| serve(domain, found) }
        end
      end

      def read_storage
        buckets = pages("R2 buckets", "/accounts/#{@account['id']}/r2/buckets", {}, %w[name location], items: "buckets")
        buckets.each { |bucket| add(ResourceMap::KIND_BUCKET, bucket["name"], bucket["name"], url: dashboard("r2/overview"), details: { "region" => bucket["location"] }.compact) }
        databases = pages("D1 databases", "/accounts/#{@account['id']}/d1/database", {}, %w[uuid name])
        databases.each { |database| add(ResourceMap::KIND_DATABASE, database["uuid"], database["name"], url: dashboard("workers/d1"), details: { "engine" => "D1" }) }
        namespaces = pages("KV namespaces", "/accounts/#{@account['id']}/storage/kv/namespaces", {}, %w[id title])
        namespaces.each { |namespace| add(ResourceMap::KIND_KV_NAMESPACE, namespace["id"], namespace["title"], url: dashboard("workers/kv/namespaces")) }
        queues = pages("Queues", "/accounts/#{@account['id']}/queues", {}, %w[queue_name consumers])
        queues.each do |queue|
          found = add(ResourceMap::KIND_QUEUE, queue["queue_name"], queue["queue_name"], url: dashboard("workers/queues"))
          Array(queue["consumers"]).filter_map { |consumer| consumer["script"] || consumer["service"] }.each do |script|
            link(key(ResourceMap::KIND_WORKER, script), found, ResourceMap::RELATION_USES)
          end
        end
      end

      def read_tunnels
        tunnels = pages("Tunnels", "/accounts/#{@account['id']}/cfd_tunnel", { is_deleted: false }, %w[id name status])
        tunnels.each { |tunnel| add(ResourceMap::KIND_TUNNEL, tunnel["id"], tunnel["name"], status: tunnel["status"], url: dashboard("tunnels")) }
        tunnels.map { |tunnel| tunnel["id"] }.each_slice(CHUNK) do |ids|
          Array(run("Tunnel routes", tunnel_script(ids))).each do |config|
            next @gaps << "The routes of a Tunnel could not be read: #{config['error']}" if config["error"]

            tunnel = key(ResourceMap::KIND_TUNNEL, config["id"])
            Array(config["ingress"]).each { |rule| serve(rule["hostname"], tunnel) if rule["hostname"].present? }
          end
        end
      end

      def read_pools
        pools = pages("load balancer pools", "/accounts/#{@account['id']}/load_balancers/pools", {}, %w[id name enabled origins])
        pools.each do |pool|
          origins = Array(pool["origins"]).map { |origin| origin["address"] }.compact
          found = add(ResourceMap::KIND_ORIGIN_POOL, pool["id"], pool["name"], status: (pool["enabled"] == false ? "disabled" : "active"),
                                                                               details: { "origins" => origins.join(", ").presence }.compact)
          origins.select { |address| address.match?(/[a-z]/i) }.each { |address| link(found, ResourceMap.domain(address).key, ResourceMap::RELATION_USES) }
        end
      end

      def read_hyperdrive
        configs = pages("Hyperdrive configurations", "/accounts/#{@account['id']}/hyperdrive/configs", {}, %w[id name origin.host origin.database])
        configs.each do |config|
          origin = [ config["origin.host"], config["origin.database"] ].compact.join("/")
          add(ResourceMap::KIND_DATABASE_PROXY, config["id"], config["name"], details: { "origin" => origin.presence }.compact)
        end
      end

      def read_access
        apps = pages("Access applications", "/accounts/#{@account['id']}/access/apps", {}, %w[id name domain])
        apps.each do |app|
          found = add(ResourceMap::KIND_ACCESS_APP, app["id"], app["name"].presence || app["domain"].to_s)
          host = host_of(app["domain"])
          next unless host

          @served << host
          link(ResourceMap.domain(host).key, found, ResourceMap::RELATION_PROTECTED_BY)
        end
      end

      # Products the live spec offers that Firefight neither reads nor leaves out on purpose.
      def not_yet
        products = run("the list of Cloudflare's products", PRODUCTS_SCRIPT, tool: SEARCH)
        return "search is switched off for Cloudflare, so what is not on the map cannot be listed." if products.nil?

        missing = Array(products) - HANDLED
        "Not on the map yet, by API path: #{missing.join(', ')}." if missing.any?
      end

      # A hostname is served by what answers for it.
      def serve(host, target)
        host = host_of(host)
        return unless host

        @served << host
        link(ResourceMap.domain(host).key, target, ResourceMap::RELATION_SERVED_BY)
      end

      # The hostname in a route pattern or an Access domain, such as app.example.com out of app.example.com/api/*.
      def host_of(pattern)
        host = pattern.to_s.split("/").first.to_s.delete_prefix("*.").strip.downcase
        host if host.match?(/\A[a-z0-9.-]+\.[a-z]{2,}\z/) && !host.include?("*")
      end

      def add(kind, id, name, status: nil, url: nil, details: {})
        found = ResourceMap::Found.new(provider: PROVIDER, account: @account["name"], kind: kind, external_id: id.to_s, name: name.to_s,
                                       status: status, url: url, details: details)
        @resources << found
        found.key
      end

      def key(kind, id) = [ PROVIDER, @account["name"], kind, id.to_s ]

      def link(from, to, relation)
        @links << ResourceMap::FoundLink.new(from: from, to: to, relation: relation)
      end

      def dashboard(page) = "#{DASHBOARD}/#{@account['id']}/#{page}"

      # Every page of a list, up to MAX_PAGES, by page number or by cursor, whichever Cloudflare answers with.
      def pages(what, path, query, fields, items: "result", per_page: PER_PAGE)
        rows = []
        cursor = nil
        (1..MAX_PAGES).each do |page|
          paging = cursor ? { cursor: cursor, per_page: per_page } : { page: page, per_page: per_page }
          body = run(what, list_script(path, query.merge(paging), fields, items: items))
          return rows unless body

          rows.concat(Array(body["items"]))
          info = body["info"] || {}
          cursor = info["cursor"].presence
          more = cursor || (info["total_pages"].to_i > page)
          return rows unless more
        end
        @gaps << "Only the first #{MAX_PAGES * per_page} #{what} were read."
        rows
      end

      def run(what, code, tool: EXECUTE)
        arguments = { "code" => code }
        arguments["account_id"] = @account["id"] if tool == EXECUTE && @account
        result = @call_tool.call(tool, arguments, what)
        if result.nil?
          @switched_off << tool
          return nil
        end

        text = Array(result["content"]).filter_map { |part| part["text"] }.join
        if result["isError"]
          raise Stop if text.match?(RATE_LIMITED)

          @gaps << "Cloudflare could not list the #{what}: #{text.lines.first.to_s.strip.truncate(200)}"
          return nil
        end
        @gaps << "Cloudflare's server cut the list of #{what} short, so some are missing." if text.include?(TRUNCATED)
        JSON.parse(text.split(TRUNCATED).first)
      rescue JSON::ParserError
        @gaps << "Cloudflare answered the #{what} with something that is not JSON."
        nil
      end

      def list_script(path, query, fields, items: "result")
        list = items == "result" ? "r.result" : "(r.result || {})[#{JSON.generate(items)}]"
        <<~JS
          async () => {
            #{PICK}
            const r = await cloudflare.request({ method: "GET", path: #{JSON.generate(path)}, query: #{JSON.generate(query)} });
            return { items: (#{list} || []).map((x) => pick(x, #{JSON.generate(fields)})), info: r.result_info || null };
          }
        JS
      end

      def bindings_script(names)
        <<~JS
          async () => {
            #{PICK}
            const out = [];
            for (const name of #{JSON.generate(names)}) {
              try {
                const r = await cloudflare.request({ method: "GET", path: "/accounts/" + accountId + "/workers/scripts/" + encodeURIComponent(name) + "/settings" });
                out.push({ name, bindings: (r.result.bindings || []).map((b) => pick(b, ["type", "bucket_name", "id", "database_id", "namespace_id", "queue_name", "service"])) });
              } catch (e) {
                out.push({ name, error: String(e.message).slice(0, 200) });
              }
            }
            return out;
          }
        JS
      end

      def tunnel_script(ids)
        <<~JS
          async () => {
            const out = [];
            for (const id of #{JSON.generate(ids)}) {
              try {
                const r = await cloudflare.request({ method: "GET", path: "/accounts/" + accountId + "/cfd_tunnel/" + id + "/configurations" });
                out.push({ id, ingress: ((r.result.config || {}).ingress || []).map((rule) => ({ hostname: rule.hostname || null })) });
              } catch (e) {
                out.push({ id, error: String(e.message).slice(0, 200) });
              }
            }
            return out;
          }
        JS
      end

      # A zone's settings, each null when it could not be read. A ruleset phase with no rules is not an error.
      def settings_script(zone_id)
        <<~JS
          async () => {
            const zone = #{JSON.generate(zone_id)};
            const get = async (path, query) => {
              try { return (await cloudflare.request({ method: "GET", path, query })).result; } catch (e) { return undefined; }
            };
            const rules = async (phase) => {
              try {
                const r = await cloudflare.request({ method: "GET", path: "/zones/" + zone + "/rulesets/phases/" + phase + "/entrypoint" });
                return (r.result.rules || []).length;
              } catch (e) {
                return /not found|10003|404/i.test(String(e.message)) ? 0 : null;
              }
            };
            const ssl = await get("/zones/" + zone + "/settings/ssl");
            const packs = await get("/zones/" + zone + "/ssl/certificate_packs", { status: "all" });
            const expiries = (packs || []).flatMap((p) => (p.certificates || []).map((c) => c.expires_on)).filter(Boolean).sort();
            const pageRules = await get("/zones/" + zone + "/pagerules");
            const dnssec = await get("/zones/" + zone + "/dnssec");
            return {
              ssl_mode: ssl ? ssl.value : null,
              certificates: packs ? packs.filter((p) => p.status === "active").length + " active" + (expiries.length ? ", next expiry " + expiries[0].slice(0, 10) : "") : null,
              waf_rules: await rules("http_request_firewall_custom"),
              rate_limit_rules: await rules("http_ratelimit"),
              cache_rules: await rules("http_request_cache_settings"),
              page_rules: pageRules ? pageRules.length : null,
              dnssec: dnssec ? dnssec.status : null
            };
          }
        JS
      end
    end
  end
end
