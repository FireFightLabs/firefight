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

      assert_equal [ { "id" => "pg1" } ], api.pages.items
      assert_equal [ { "id" => "i1" } ], api.incidents("pg1", statuses: %w[INVESTIGATING IDENTIFIED]).items
      assert_equal "i1", api.incident("pg1", "i1")["id"]
      assert_empty api.maintenances("pg1").items
      assert_equal "m1", api.maintenance("pg1", "m1")["id"]
      assert_empty api.subscribers("pg1", search: "ana", status: "confirmed").items
      assert_empty api.templates("pg1").items
      assert_equal "c1", api.component("pg1", "c1")["id"]
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
      expect_write(Net::HTTP::Post, "/v1/pg1/incidents/t1", {}, { id: "i2" })

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
      assert_equal "i2", api.create_incident_from_template("pg1", "t1")["id"]
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
