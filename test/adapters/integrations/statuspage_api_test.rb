require "test_helper"

module Integrations
  class StatuspageApiTest < ActiveSupport::TestCase
    test "a read goes to the Manage API with the key as Statuspage's OAuth header and pages until a page comes back short" do
      first = Array.new(StatuspageApi::PER_PAGE) { |index| { id: "c#{index}" } }
      Http.expects(:request).with do |uri, request, **|
        uri.host == "api.statuspage.io" && uri.path == "/v1/pages/pg1/components" && request["Authorization"] == "OAuth sp-key" &&
          URI.decode_www_form(uri.query).to_h == { "page" => "1", "per_page" => StatuspageApi::PER_PAGE.to_s }
      end.returns(response(200, first))
      Http.expects(:request).with { |uri, *| URI.decode_www_form(uri.query).to_h["page"] == "2" }.returns(response(200, [ { id: "last" } ]))

      read = StatuspageApi.new("sp-key").components("pg1")

      assert_equal StatuspageApi::PER_PAGE + 1, read.items.size
      assert read.complete
    end

    test "incidents are listed by the kind asked for, searched with q and limit, and subscribers page from zero" do
      api = StatuspageApi.new("sp-key")
      expect_get("/v1/pages/pg1/incidents/unresolved", [], "page" => "1", "per_page" => "100")
      expect_get("/v1/pages/pg1/incidents/active_maintenance", [], "page" => "1", "per_page" => "100")
      expect_get("/v1/pages/pg1/incidents", [ { id: "i1" } ], "q" => "checkout", "limit" => "100", "page" => "1")
      expect_get("/v1/pages/pg1/subscribers", [], "type" => "email", "state" => "all", "limit" => "100", "page" => "0")
      expect_get("/v1/pages/pg1/subscribers/count", { email: 3 }, "state" => "active")

      assert_empty api.incidents("pg1", StatuspageApi::INCIDENTS_UNRESOLVED).items
      assert_empty api.incidents("pg1", StatuspageApi::INCIDENTS_ACTIVE_MAINTENANCE).items
      assert_equal [ { "id" => "i1" } ], api.incidents("pg1", StatuspageApi::INCIDENTS_ALL, query: "checkout").items
      assert_empty api.subscribers("pg1", type: "email", state: "all").items
      assert_equal 3, api.subscriber_count("pg1", state: "active")["email"]
    end

    test "changes are sent as JSON under the root key Statuspage documents for each, and an id never reaches another path" do
      api = StatuspageApi.new("sp-key")
      expect_write(Net::HTTP::Patch, "/v1/pages/pg1", { "page" => { "name" => "Acme status" } }, { id: "pg1" })
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/incidents", { "incident" => { "name" => "Checkout down" } }, { id: "i1" })
      expect_write(Net::HTTP::Patch, "/v1/pages/pg1/incidents/i1", { "incident" => { "status" => "resolved", "body" => "Fixed" } }, { id: "i1" })
      expect_write(Net::HTTP::Patch, "/v1/pages/pg1/incidents/i1/incident_updates/u1", { "incident_update" => { "body" => "Fixed it" } }, { id: "u1" })
      expect_write(Net::HTTP::Delete, "/v1/pages/pg1/incidents/i1", nil, { id: "i1" })
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/components", { "component" => { "name" => "API" } }, { id: "c1" })
      expect_write(Net::HTTP::Patch, "/v1/pages/pg1/components/c%2F1", { "component" => { "status" => "major_outage" } }, { id: "c/1" })
      expect_write(Net::HTTP::Delete, "/v1/pages/pg1/components/c1", nil, nil)
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/component-groups", { "component_group" => { "name" => "Core", "components" => [ "c1" ] } }, { id: "g1" })
      expect_write(Net::HTTP::Patch, "/v1/pages/pg1/component-groups/g1", { "component_group" => { "name" => "Core", "components" => [ "c1" ] } }, { id: "g1" })
      expect_write(Net::HTTP::Delete, "/v1/pages/pg1/component-groups/g1", nil, { id: "g1" })
      expect_write(Net::HTTP::Put, "/v1/pages/pg1/incidents/i1/postmortem", { "postmortem" => { "body_draft" => "What happened" } }, { body_draft: "What happened" })
      expect_write(Net::HTTP::Put, "/v1/pages/pg1/incidents/i1/postmortem/publish", { "postmortem" => { "notify_subscribers" => false } }, { published_at: "x" })
      expect_write(Net::HTTP::Put, "/v1/pages/pg1/incidents/i1/postmortem/revert", nil, {})
      expect_write(Net::HTTP::Delete, "/v1/pages/pg1/incidents/i1/postmortem", nil, nil)
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/incident_templates", { "template" => { "name" => "DB", "title" => "Database", "body" => "Slow" } }, { id: "t1" })
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/subscribers", { "subscriber" => { "email" => "ana@acme.io" } }, { id: "s1" })
      expect_write(Net::HTTP::Patch, "/v1/pages/pg1/subscribers/s1", { "component_ids" => [ "c1" ] }, { id: "s1" })
      expect_write(Net::HTTP::Delete, "/v1/pages/pg1/subscribers/s1?skip_unsubscription_notification=true", nil, { id: "s1" })
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/subscribers/s1/resend_confirmation", nil, nil)
      expect_write(Net::HTTP::Post, "/v1/pages/pg1/incidents/i1/subscribers", { "subscriber" => { "email" => "ana@acme.io" } }, { id: "s2" })
      expect_write(Net::HTTP::Delete, "/v1/pages/pg1/incidents/i1/subscribers/s2", nil, { id: "s2" })

      api.update_page("pg1", "name" => "Acme status")
      api.create_incident("pg1", "name" => "Checkout down")
      api.update_incident("pg1", "i1", "status" => "resolved", "body" => "Fixed")
      api.edit_incident_update("pg1", "i1", "u1", "body" => "Fixed it")
      api.delete_incident("pg1", "i1")
      api.create_component("pg1", "name" => "API")
      assert_equal "c/1", api.update_component("pg1", "c/1", "status" => "major_outage")["id"]
      assert_equal({}, api.delete_component("pg1", "c1"))
      api.create_component_group("pg1", name: "Core", components: [ "c1" ])
      api.update_component_group("pg1", "g1", name: "Core", components: [ "c1" ])
      api.delete_component_group("pg1", "g1")
      api.draft_postmortem("pg1", "i1", "What happened")
      api.publish_postmortem("pg1", "i1", "notify_subscribers" => false)
      api.revert_postmortem("pg1", "i1")
      api.delete_postmortem("pg1", "i1")
      api.create_template("pg1", "name" => "DB", "title" => "Database", "body" => "Slow")
      api.add_subscriber("pg1", "email" => "ana@acme.io")
      api.update_subscriber("pg1", "s1", [ "c1" ])
      api.unsubscribe("pg1", "s1", quietly: true)
      api.resend_confirmation("pg1", "s1")
      api.add_incident_subscriber("pg1", "i1", "email" => "ana@acme.io")
      api.remove_incident_subscriber("pg1", "i1", "s2")
    end

    test "Statuspage's refusal is raised in its own words, a key it does not take is its own error, and 420 and 429 are rate limited" do
      Http.stubs(:request).returns(response(404, { message: "The requested resource could not be found." }))
      error = assert_raises(StatuspageApi::Error) { StatuspageApi.new("sp-key").incident("pg1", "nope") }
      assert_equal "Statuspage answered 404: The requested resource could not be found.", error.message
      assert_kind_of Integrations::NotFound, error

      Http.stubs(:request).returns(response(401, { error: "Could not authenticate" }))
      assert_raises(StatuspageApi::Unauthenticated) { StatuspageApi.new("bad").pages }
      Http.stubs(:request).returns(response(420, { error: "Rate limited" }))
      assert_kind_of Integrations::RateLimited, assert_raises(StatuspageApi::Error) { StatuspageApi.new("sp-key").pages }
      Http.stubs(:request).returns(response(429, { error: "Rate limited" }))
      assert_kind_of Integrations::RateLimited, assert_raises(StatuspageApi::Error) { StatuspageApi.new("sp-key").pages }
    end

    test "a page's public address is its own domain, or its Statuspage subdomain, and an incident's is its shortlink or under the page" do
      assert_equal "https://status.acme.io", StatuspageApi.public_url("domain" => "status.acme.io", "subdomain" => "acme")
      assert_equal "https://acme.statuspage.io", StatuspageApi.public_url("domain" => "", "subdomain" => "acme")
      assert_equal "https://acme.statuspage.io", StatuspageApi.public_url("subdomain" => "acme.statuspage.io")
      assert_nil StatuspageApi.public_url("subdomain" => "")
    end

    private

    def expect_get(path, body, query)
      Http.expects(:request).with do |uri, request, **|
        request.is_a?(Net::HTTP::Get) && uri.path == path && URI.decode_www_form(uri.query.to_s).to_h == query
      end.returns(response(200, body))
    end

    def expect_write(method, path, body, answer)
      wanted_path, wanted_query = path.split("?")
      Http.expects(:request).with do |uri, request, **|
        request.is_a?(method) && uri.path == wanted_path && uri.query == wanted_query && request["Authorization"] == "OAuth sp-key" &&
          (body.nil? ? request.body.nil? : JSON.parse(request.body) == body)
      end.returns(answer.nil? ? stub(code: "204", body: "") : response(200, answer))
    end

    def response(code, body)
      stub(code: code.to_s, body: body.to_json)
    end
  end
end
