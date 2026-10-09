require "test_helper"

module Integrations
  module ReadGuards
    class CloudflareTest < ActiveSupport::TestCase
      test "a read is taken as data and Firefight writes the script, every value a JSON literal" do
        sent = Cloudflare.reading("execute", "method" => "get", "path" => "/zones/abc/dns_records", "query" => { "name" => "\"}); x(" },
                                             "account_id" => "acc")

        assert_equal 'async () => cloudflare.request({"method":"GET","path":"/zones/abc/dns_records","query":{"name":"\\"}); x("}})', sent["code"]
        assert_equal "acc", sent["account_id"]
      end

      test "a GraphQL Analytics query is sent as a POST to /graphql, with its variables" do
        sent = Cloudflare.reading("execute", "method" => "POST", "path" => "/graphql", "graphql" => "{ viewer { zones { zoneTag } } }",
                                             "variables" => { "zone" => "abc" })["code"]

        assert_includes sent, '{"method":"POST","path":"/graphql","body":{"query":"{ viewer { zones { zoneTag } } }","variables":{"zone":"abc"}}}'
      end

      test "a Workers log query is the one other POST taken, with its body as data" do
        path = "/accounts/acc/workers/observability/telemetry/query"
        sent = Cloudflare.reading("execute", "method" => "POST", "path" => path, "body" => { "queryId" => "q", "parameters" => { "view" => "events" } })["code"]

        assert_includes sent, %({"method":"POST","path":"#{path}","body":{"queryId":"q","parameters":{"view":"events"}}})
        assert_raises(Refused) { Cloudflare.reading("execute", "method" => "POST", "path" => path, "body" => "events") }
        assert_raises(PolicyRefusal) { Cloudflare.reading("execute", "method" => "POST", "path" => "/accounts/acc/workers/scripts/api/deployments", "body" => {}) }
      end

      test "a script Firefight wrote for a read is a read, and a script someone wrote is one only as a single GET" do
        written = Cloudflare.reading("execute", "method" => "GET", "path" => "/accounts/acc/pages/projects/ember")
        graphql = Cloudflare.reading("execute", "method" => "POST", "path" => "/graphql", "graphql" => "{ viewer { zones { zoneTag } } }")
        assert Cloudflare.reads?("execute", written)
        assert Cloudflare.reads?("execute", graphql)

        # The script Halon wrote in the chat this was seen in.
        assert Cloudflare.reads?("execute", "code" => "async () => { return await cloudflare.request({method:'GET', path:'/accounts/'+accountId+'/pages/projects/ember-landing'}); }")
        assert Cloudflare.reads?("execute", "code" => "async () => cloudflare.request({ path: '/zones', method: \"GET\", query: { per_page: 50 } })")

        [
          "async () => cloudflare.request({method:'DELETE', path:'/zones/abc'})",
          "async () => { await cloudflare.request({method:'GET', path:'/zones'}); return cloudflare.request({method:'DELETE', path:'/zones/abc'}); }",
          "async () => cloudflare.request({method:'GET', path:'/zones', method:'DELETE'})",
          "async () => cloudflare.request({method: verb, path:'/zones'})",
          "async () => cloudflare.request({ method: \"GET\", [\"meth\" + \"od\"]: \"DELETE\", path: \"/zones/x\" })",
          "async () => cloudflare.request({ method: 'GET', \"\\u006dethod\": 'DELETE', path: '/zones/x' })",
          "async () => cloudflare.request({ method: 'GET', ...{ path: '/zones/x' } })",
          "async () => cloudflare.request({ method: 'GET', ...{ method: 'DELETE' }, path: '/zones/x' })",
          "async () => cloudflare.request({\"method\":\"POST\",\"path\":\"/graphql\",\"body\":{\"query\":\"mutation { purge }\"}})",
          "async () => fetch('https://example.com')"
        ].each { |code| assert_not Cloudflare.reads?("execute", "code" => code), code }
      end

      test "a call that would change something is refused by Firefight's rule before anything is sent" do
        [
          { "method" => "DELETE", "path" => "/zones/abc" },
          { "method" => "POST", "path" => "/zones/abc/purge_cache" },
          { "method" => "POST", "path" => "/graphql", "graphql" => "mutation { x }" }
        ].each do |arguments|
          assert_raises(PolicyRefusal, arguments.inspect) { Cloudflare.reading("execute", arguments) }
        end
      end

      test "a read that is not shaped the way the guard takes one is refused before anything is sent, for the call to be fixed" do
        [
          { "method" => "GET", "path" => "/zones/../accounts" },
          { "method" => "GET", "path" => "zones" },
          { "method" => "GET", "path" => "/zones", "query" => "per_page=5" },
          { "code" => "async () => cloudflare.request({ method: 'DELETE', path: '/zones/abc' })" }
        ].each do |arguments|
          error = assert_raises(Refused, arguments.inspect) { Cloudflare.reading("execute", arguments) }
          assert_not_kind_of PolicyRefusal, error
        end
      end
    end
  end
end
