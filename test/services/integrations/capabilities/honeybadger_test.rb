require "test_helper"

class Integrations::Capabilities::HoneybadgerTest < ActiveSupport::TestCase
  include ObserverTestHelper

  setup do
    run_web_on_northflank
    serve_hostname("shop.acme.com")
    projects = [ { "id" => 11, "name" => "Web", "sites" => [ { "id" => "s1", "name" => "Shop", "url" => "https://shop.acme.com" } ] }, { "id" => 12, "name" => "Worker", "sites" => [] } ]
    @row = watch_with("honeybadger", "Honeybadger", { "list_faults" => %w[project_id q created_after occurred_after occurred_before limit order page], "get_project" => %w[id] },
                      learned: { "projects" => projects })
  end

  test "Honeybadger answers a service's open errors from the project of its name, since a whole minute" do
    travel_to Time.utc(2026, 10, 4, 10, 0, 30) do
      errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web", "text" => "Timeout", "minutes" => 30)

      assert_equal [ @row, "list_faults" ], [ errors.environment_row, errors.tool.name ]
      assert_equal({ "project_id" => 11, "q" => "-is:resolved -is:ignored \"Timeout\"", "occurred_after" => "2026-10-04T09:30:00Z", "order" => "recent", "limit" => 25 },
                   errors.arguments)
    end
    errors = resolve(Integrations::Capabilities::ERRORS, "resource" => "web")
    faults = { "results" => [ { "id" => 5, "klass" => "Net::ReadTimeout", "message" => "execution expired", "notices_count" => 40,
                                "last_notice_at" => "2026-10-04T09:59:00Z", "environment" => "production", "url" => "https://app.honeybadger.io/projects/11/faults/5" } ],
               "links" => { "next" => "x" } }
    text = errors.present_result(answer(faults))["content"].first["text"]
    assert_match "Net::ReadTimeout: execution expired, 40 times, last 2026-10-04T09:59:00Z, production, https://app.honeybadger.io/projects/11/faults/5", text
    assert_match "There are more", text
  end

  test "a hostname's status is the uptime sites that check it, and never the rest of the project" do
    status = resolve(Integrations::Capabilities::STATUS, "resource" => "shop.acme.com", "connection" => "honeybadger")
    assert_equal [ "get_project", { "id" => 11 } ], [ status.tool.name, status.arguments ]

    project = { "name" => "Web", "token" => "secret", "sites" => [ { "id" => "s1", "name" => "Shop", "url" => "https://shop.acme.com", "state" => "down", "active" => true },
                                                                   { "id" => "s2", "name" => "Other", "url" => "https://other.example", "state" => "up" } ] }
    text = status.present_result(answer(project))["content"].first["text"]
    assert_equal "Honeybadger uptime checks of Web:\nShop (https://shop.acme.com): down", text
  end

  test "a service with no project of its name is said" do
    ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE, external_id: "api-id", name: "api",
                                  integration_environment: @northflank_row, first_seen_at: Time.current, last_seen_at: Time.current)

    assert_match "No Honeybadger project is called api", unroutable(Integrations::Capabilities::ERRORS, "resource" => "api")
  end
end
