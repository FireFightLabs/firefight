require "test_helper"

module Integrations
  class InstatusApiTest < ActiveSupport::TestCase
    test "a read goes to Instatus's API with the key as a bearer token and pages until a page comes back short" do
      first = Array.new(InstatusApi::PER_PAGE) { |index| { id: "c#{index}" } }
      Http.expects(:request).with do |uri, request, **|
        uri.host == "api.instatus.com" && uri.path == "/v2/pg1/components" && request["Authorization"] == "Bearer in-key" &&
          URI.decode_www_form(uri.query).to_h == { "page" => "1", "per_page" => InstatusApi::PER_PAGE.to_s }
      end.returns(response(200, first))
      Http.expects(:request).with { |uri, *| URI.decode_www_form(uri.query).to_h["page"] == "2" }.returns(response(200, [ { id: "last" } ]))

      read = InstatusApi.new("in-key").components("pg1")

      assert_equal InstatusApi::PER_PAGE + 1, read.items.size
      assert read.complete
    end

    test "pages, incidents, maintenances and subscribers are read where Instatus documents each" do
      api = InstatusApi.new("in-key")
      expect_get("/v2/pages", [ { id: "pg1" } ])
      expect_get("/v1/pg1/incidents", [ { id: "i1" } ], "status" => "INVESTIGATING,IDENTIFIED")
      expect_get("/v1/pg1/incidents/i1", { id: "i1" })
      expect_get("/v2/pg1/maintenances", [])
      expect_get("/v1/pg1/maintenances/m1", { id: "m1" })
      expect_get("/v2/pg1/subscribers", [], "search" => "ana", "status" => "confirmed")
      expect_get("/v1/pg1/templates", [])
      expect_get("/v2/pg1/components/c1", { id: "c1" })
      expect_get("/v1/pg1/templates/t1", { id: "t1" })

      assert_equal [ { "id" => "pg1" } ], api.pages.items
      assert_equal [ { "id" => "i1" } ], api.incidents("pg1", statuses: %w[INVESTIGATING IDENTIFIED]).items
      assert_equal "i1", api.incident("pg1", "i1")["id"]
      assert_empty api.maintenances("pg1").items
      assert_equal "m1", api.maintenance("pg1", "m1")["id"]
      assert_empty api.subscribers("pg1", search: "ana", status: "confirmed").items
      assert_empty api.templates("pg1").items
      assert_equal "c1", api.component("pg1", "c1")["id"]
      assert_equal "t1", api.template("pg1", "t1")["id"]
    end

    test "changes are sent as JSON with the method and version Instatus documents for each, and an id never reaches another path" do
      api = InstatusApi.new("in-key")
      expect_write(Net::HTTP::Post, "/v1/pages", { "name" => "Acme", "subdomain" => "acme" }, { id: "pg2" })
      expect_write(Net::HTTP::Put, "/v2/pg1", { "name" => "Acme status" }, { id: "pg1" })
      expect_write(Net::HTTP::Delete, "/v2/pg2", nil, { id: "pg2" })
      expect_write(Net::HTTP::Post, "/v1/pg1/incidents", { "name" => "Checkout down", "status" => "INVESTIGATING" }, { id: "i1" })
      expect_write(Net::HTTP::Put, "/v1/pg1/incidents/i1", { "status" => "RESOLVED" }, { id: "i1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/incidents/i1/incident-updates", { "message" => "Fixed" }, { id: "u1" })
      expect_write(Net::HTTP::Put, "/v1/pg1/incidents/i1/incident-updates/u1", { "message" => "Fixed it" }, { id: "u1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/incidents/i1/incident-updates/u1", nil, { id: "u1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/incidents/i1", nil, { id: "i1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/components", { "name" => "API" }, { id: "c1" })
      expect_write(Net::HTTP::Put, "/v2/pg1/components/c%2F1", { "status" => "MAJOROUTAGE" }, { id: "c/1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/components/c1", nil, { id: "c1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/maintenances", { "name" => "Upgrade" }, { id: "m1" })
      expect_write(Net::HTTP::Put, "/v1/pg1/maintenances/m1", { "status" => "INPROGRESS" }, { id: "m1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/maintenances/m1/maintenance-updates", { "message" => "Started" }, { id: "u2" })
      expect_write(Net::HTTP::Put, "/v1/pg1/maintenances/m1/maintenance-updates/u2", { "message" => "Begun" }, { id: "u2" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/maintenances/m1/maintenance-updates/u2", nil, { id: "u2" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/maintenances/m1", nil, { id: "m1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/subscribers", { "email" => "ana@acme.io", "all" => true }, { id: "s1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/subscribers/s1", nil, { id: "s1" })

      api.create_page("name" => "Acme", "subdomain" => "acme")
      api.update_page("pg1", "name" => "Acme status")
      api.delete_page("pg2")
      api.create_incident("pg1", "name" => "Checkout down", "status" => "INVESTIGATING")
      api.update_incident("pg1", "i1", "status" => "RESOLVED")
      api.add_incident_update("pg1", "i1", "message" => "Fixed")
      api.edit_incident_update("pg1", "i1", "u1", "message" => "Fixed it")
      api.delete_incident_update("pg1", "i1", "u1")
      api.delete_incident("pg1", "i1")
      api.create_component("pg1", "name" => "API")
      assert_equal "c/1", api.update_component("pg1", "c/1", "status" => "MAJOROUTAGE")["id"]
      api.delete_component("pg1", "c1")
      api.create_maintenance("pg1", "name" => "Upgrade")
      api.update_maintenance("pg1", "m1", "status" => "INPROGRESS")
      api.add_maintenance_update("pg1", "m1", "message" => "Started")
      api.edit_maintenance_update("pg1", "m1", "u2", "message" => "Begun")
      api.delete_maintenance_update("pg1", "m1", "u2")
      api.delete_maintenance("pg1", "m1")
      api.add_subscriber("pg1", "email" => "ana@acme.io", "all" => true)
      api.remove_subscriber("pg1", "s1")
    end

    test "monitors page with page and limit until the last of totalPages, at the paths Instatus documents without a version" do
      Http.expects(:request).with do |uri, request, **|
        request.is_a?(Net::HTTP::Get) && uri.path == "/pg1/monitors" &&
          URI.decode_www_form(uri.query).to_h == { "page" => "1", "limit" => InstatusApi::MONITOR_LIMIT.to_s, "status" => "DOWN" }
      end.returns(response(200, { monitors: [ { id: "m1" } ], total: 2, page: 1, totalPages: 2, limit: 100 }))
      Http.expects(:request).with { |uri, *| URI.decode_www_form(uri.query).to_h["page"] == "2" }
          .returns(response(200, { monitors: [ { id: "m2" } ], total: 2, page: 2, totalPages: 2, limit: 100 }))

      read = InstatusApi.new("in-key").monitors("pg1", status: "DOWN")

      assert_equal %w[m1 m2], read.items.map { |monitor| monitor["id"] }
      assert read.complete
    end

    test "monitor, alert, group, cron, metric, teammate, notice and outage calls go where Instatus documents each" do
      api = InstatusApi.new("in-key")
      expect_get("/monitors/m1/logs", { monitorLogs: [], total: 0 }, "limit" => "50", "status" => "DOWN")
      expect_get("/monitors/m1/run", { status: "success" }, "location" => "EU_CENTRAL_1")
      expect_get("/pg1/monitor-alerts", { monitorAlerts: [], totalPages: 1 }, "limit" => InstatusApi::MONITOR_LIMIT.to_s)
      expect_get("/monitors-groups/g1/run", { result: "OK" }, {})
      expect_get("/pg1/monitors/cron", { cronMonitors: [], totalPages: 1 }, "limit" => InstatusApi::MONITOR_LIMIT.to_s)
      expect_get("/monitors/cron/k1/logs", { logs: [] }, "limit" => "50", "importance" => "important")
      expect_get("/monitors/cron/k1/summary", { summary: { availability: 99.5 } }, {})
      expect_get("/v1/pg1/metrics", [], {})
      expect_get("/v1/pg1/metrics/x1", { id: "x1" }, {})
      expect_get("/v1/pg1/team", [], {})
      expect_get("/v1/pg1/generic-notices", [], {})
      expect_get("/v1/pg1/outages", [], {})

      assert_empty api.monitor_logs("m1", limit: 50, status: "DOWN")["monitorLogs"]
      assert_equal "success", api.run_monitor("m1", location: "EU_CENTRAL_1")["status"]
      assert_empty api.monitor_alerts("pg1").items
      assert_equal "OK", api.run_monitor_group("g1")["result"]
      assert_empty api.cron_monitors("pg1").items
      assert_empty api.cron_logs("k1", limit: 50, important: true)["logs"]
      assert_in_delta 99.5, api.cron_summary("k1").dig("summary", "availability")
      assert_empty api.metrics("pg1").items
      assert_equal "x1", api.metric("pg1", "x1")["id"]
      assert_empty api.teammates("pg1").items
      assert_empty api.notices("pg1").items
      assert_empty api.outages("pg1").items

      expect_write(Net::HTTP::Post, "/monitors", { "pageId" => "pg1", "url" => "https://acme.io" }, { monitor: { id: "m3" } })
      expect_write(Net::HTTP::Put, "/monitors/m3", { "name" => "Acme" }, { monitor: { id: "m3" } })
      expect_write(Net::HTTP::Delete, "/monitors/m3", nil, { message: "deleted" })
      expect_write(Net::HTTP::Post, "/monitor-alerts", { "pageId" => "pg1", "type" => "EMAIL" }, { monitor: { id: "a1" } })
      expect_write(Net::HTTP::Put, "/monitor-alerts/a1", { "monitors" => [ "m3" ] }, { monitor: { id: "a1" } })
      expect_write(Net::HTTP::Delete, "/monitor-alerts/a1", nil, { message: "deleted" })
      expect_write(Net::HTTP::Post, "/monitors-groups", { "pageId" => "pg1", "name" => "Core" }, { monitor: { id: "g1" } })
      expect_write(Net::HTTP::Put, "/monitors-groups/g1", { "name" => "Edge" }, { monitor: { id: "g1" } })
      expect_write(Net::HTTP::Post, "/monitors-groups/g1/monitors", { "monitors" => [ "m3" ] }, { message: "added" })
      expect_write(Net::HTTP::Delete, "/monitors-groups/g1", nil, { message: "deleted" })
      expect_write(Net::HTTP::Post, "/monitors/cron", { "pageId" => "pg1", "name" => "Backup" }, { cronMonitor: { id: "k1" } })
      expect_write(Net::HTTP::Put, "/monitors/cron/k1", { "state" => "PAUSED" }, { cronMonitor: { id: "k1" } })
      expect_write(Net::HTTP::Delete, "/monitors/cron/k1", nil, { cronMonitor: { id: "k1" } })
      expect_write(Net::HTTP::Post, "/v1/pg1/metrics", { "name" => "Latency" }, { id: "x2" })
      expect_write(Net::HTTP::Put, "/v1/pg1/metrics/x2", { "suffix" => "ms" }, { id: "x2" })
      expect_write(Net::HTTP::Post, "/v1/pg1/metrics/x2/data", { "data" => [ { "timestamp" => 1, "value" => 2 } ] }, [])
      expect_write(Net::HTTP::Delete, "/v1/pg1/metrics/x2/data", nil, { name: "Latency" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/metrics/x2", nil, nil)
      expect_write(Net::HTTP::Post, "/v1/pg1/team", { "email" => "bo@acme.io" }, { id: "t1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/team/t1", nil, { memberId: "t1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/generic-notices", { "name" => "DNS" }, { id: "n1" })
      expect_write(Net::HTTP::Put, "/v1/pg1/generic-notices/n1", { "isCollapsed" => true }, { id: "n1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/generic-notices/n1", nil, { id: "n1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/outages", { "componentId" => "c1" }, { id: "o1" })
      expect_write(Net::HTTP::Put, "/v1/pg1/outages/o1", { "status" => "MAJOROUTAGE" }, { id: "o1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/outages/o1", nil, nil)

      api.create_monitor("pageId" => "pg1", "url" => "https://acme.io")
      api.update_monitor("m3", "name" => "Acme")
      api.delete_monitor("m3")
      api.create_monitor_alert("pageId" => "pg1", "type" => "EMAIL")
      api.update_monitor_alert("a1", "monitors" => [ "m3" ])
      api.delete_monitor_alert("a1")
      api.create_monitor_group("pageId" => "pg1", "name" => "Core")
      api.update_monitor_group("g1", "name" => "Edge")
      api.add_monitors_to_group("g1", [ "m3" ])
      api.delete_monitor_group("g1")
      api.create_cron_monitor("pageId" => "pg1", "name" => "Backup")
      api.update_cron_monitor("k1", "state" => "PAUSED")
      api.delete_cron_monitor("k1")
      api.create_metric("pg1", "name" => "Latency")
      api.update_metric("pg1", "x2", "suffix" => "ms")
      api.add_metric_data("pg1", "x2", [ { "timestamp" => 1, "value" => 2 } ])
      api.delete_metric_data("pg1", "x2")
      api.delete_metric("pg1", "x2")
      api.add_teammate("pg1", "bo@acme.io")
      api.remove_teammate("pg1", "t1")
      api.create_notice("pg1", "name" => "DNS")
      api.update_notice("pg1", "n1", "isCollapsed" => true)
      api.delete_notice("pg1", "n1")
      api.create_outage("pg1", "componentId" => "c1")
      api.update_outage("pg1", "o1", "status" => "MAJOROUTAGE")
      api.delete_outage("pg1", "o1")
    end

    test "workspace, audience group, integration, routing, escalation and on-call calls go where Instatus documents each, spelling and version included" do
      api = InstatusApi.new("in-key")
      expect_get("/v1/workspaces", [], {})
      expect_get("/v1/pg1/audience-groups", [], {})
      expect_get("/pg1/routing-rules", { routingRules: [ { id: "r1" } ] }, {})
      expect_get("/pg1/escalation-policies", { escalationPolicies: [ { id: "e1" } ] }, {})
      expect_get("/on-call-schedules/s1/members", { currentMembers: [], nextMembers: [], allMembers: [] }, {})

      assert_empty api.workspaces.items
      assert_empty api.audience_groups("pg1").items
      assert_equal [ { "id" => "r1" } ], api.routing_rules("pg1")
      assert_equal [ { "id" => "e1" } ], api.escalation_policies("pg1")
      assert_empty api.on_call_members("s1")["currentMembers"]

      expect_write(Net::HTTP::Post, "/v1/workspaces", { "name" => "Ops", "slug" => "ops" }, { id: "w1" })
      expect_write(Net::HTTP::Delete, "/v1/workspaces/w1", nil, { id: "w1" })
      expect_write(Net::HTTP::Post, "/v1/pg1/audience_groups", { "name" => "Partners", "components" => [ "c1" ] }, { id: "ag1" })
      expect_write(Net::HTTP::Put, "/v1/pg1/audience_groups/ag1", { "teammates" => [ "t1" ] }, { id: "ag1" })
      expect_write(Net::HTTP::Delete, "/v1/pg1/audience-groups/ag1", nil, { id: "ag1" })
      expect_write(Net::HTTP::Post, "/v3/integrations", { "pageId" => "pg1", "integrationType" => "PINGDOM" }, { integration: { id: "i1" } })
      expect_write(Net::HTTP::Put, "/v3/integrations/i1", { "label" => "Pingdom" }, { integration: { id: "i1" } })
      expect_write(Net::HTTP::Delete, "/v3/integrations/i1", nil, {})
      expect_write(Net::HTTP::Post, "/routing-rules", { "routingRule" => { "siteId" => "pg1", "order" => 1 } }, { routingRule: { id: "r2" } })
      expect_write(Net::HTTP::Put, "/routing-rules/r2", { "routingRule" => { "id" => "r2", "siteId" => "pg1", "order" => 2 } }, { routingRule: { id: "r2" } })
      expect_write(Net::HTTP::Delete, "/routing-rules/r2", nil, {})
      expect_write(Net::HTTP::Post, "/escalation-policies", { "pageId" => "pg1", "name" => "Primary" }, { escalationPolicy: { id: "e2" } })
      expect_write(Net::HTTP::Put, "/escalation-policies/e2", { "pageId" => "pg1", "name" => "Main" }, { escalationPolicy: { id: "e2" } })
      expect_write(Net::HTTP::Delete, "/escalation-policies/e2", nil, {})
      expect_write(Net::HTTP::Post, "/on-call-schedules", { "name" => "Primary", "onCallShifts" => [] }, { id: "s2" })
      expect_write(Net::HTTP::Put, "/on-call-schedules/s2", { "id" => "s2", "name" => "Main" }, { id: "s2" })
      expect_write(Net::HTTP::Delete, "/on-call-schedules/s2", nil, {})

      api.create_workspace("name" => "Ops", "slug" => "ops")
      api.delete_workspace("w1")
      api.create_audience_group("pg1", "name" => "Partners", "components" => [ "c1" ])
      api.update_audience_group("pg1", "ag1", "teammates" => [ "t1" ])
      api.delete_audience_group("pg1", "ag1")
      api.create_integration("pageId" => "pg1", "integrationType" => "PINGDOM")
      api.update_integration("i1", "label" => "Pingdom")
      api.delete_integration("i1")
      api.create_routing_rule("siteId" => "pg1", "order" => 1)
      api.update_routing_rule("r2", "id" => "r2", "siteId" => "pg1", "order" => 2)
      api.delete_routing_rule("r2")
      api.create_escalation_policy("pageId" => "pg1", "name" => "Primary")
      api.update_escalation_policy("e2", "pageId" => "pg1", "name" => "Main")
      api.delete_escalation_policy("e2")
      api.create_on_call_schedule("name" => "Primary", "onCallShifts" => [])
      api.update_on_call_schedule("s2", "id" => "s2", "name" => "Main")
      api.delete_on_call_schedule("s2")
    end

    test "Instatus's refusal is raised in its own words, a key it does not know is its own error, and a 429 is rate limited" do
      Http.stubs(:request).returns(response(404, { error: { code: "page_not_found", message: "There is no status page with this ID." } }))
      error = assert_raises(InstatusApi::Error) { InstatusApi.new("in-key").incident("nope", "i1") }
      assert_equal "Instatus answered 404: There is no status page with this ID.", error.message
      assert_kind_of Integrations::NotFound, error

      Http.stubs(:request).returns(response(401, { error: { code: "forbidden", message: "API key does not belong to a user." } }))
      assert_raises(InstatusApi::Unauthenticated) { InstatusApi.new("bad").pages }
      Http.stubs(:request).returns(response(429, { error: { code: "too_many_requests", message: "Slow down" } }))
      assert_kind_of Integrations::RateLimited, assert_raises(InstatusApi::Error) { InstatusApi.new("in-key").pages }
    end

    test "a list longer than the pages read is said to be cut short" do
      full = Array.new(InstatusApi::PER_PAGE) { |index| { id: index } }
      Http.stubs(:request).returns(response(200, full))

      read = InstatusApi.new("in-key").subscribers("pg1")

      assert_equal InstatusApi::PER_PAGE * InstatusApi::MAX_PAGES, read.items.size
      assert read.incomplete?
    end

    private

    def expect_get(path, body, query = {})
      Http.expects(:request).with do |uri, request, **|
        given = URI.decode_www_form(uri.query.to_s).to_h.except("page", "per_page")
        request.is_a?(Net::HTTP::Get) && uri.path == path && given == query
      end.returns(response(200, body))
    end

    def expect_write(method, path, body, answer)
      Http.expects(:request).with do |uri, request, **|
        request.is_a?(method) && uri.path == path && request["Authorization"] == "Bearer in-key" &&
          (body.nil? ? request.body.nil? : JSON.parse(request.body) == body)
      end.returns(response(200, answer))
    end

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
