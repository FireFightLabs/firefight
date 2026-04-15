require "test_helper"
require Rails.root.join("app/middleware/subdomain_router")

class SubdomainRouterTest < ActiveSupport::TestCase
  def setup
    @app = ->(env) { [ 200, {}, [ "OK" ] ] }
    ENV["SUBDOMAIN_ROUTING"] = "strict"
    @middleware = SubdomainRouter.new(@app)
  end

  def teardown
    ENV.delete("SUBDOMAIN_ROUTING")
  end

  def request(host, path)
    @middleware.call({ "HTTP_HOST" => host, "PATH_INFO" => path })
  end

  def assert_allowed(host, path)
    status, _, _ = request(host, path)
    assert_equal 200, status, "expected #{host}#{path} to be allowed"
  end

  def assert_blocked(host, path)
    status, _, _ = request(host, path)
    assert_equal 404, status, "expected #{host}#{path} to be blocked"
  end

  test "disabled mode passes everything" do
    ENV.delete("SUBDOMAIN_ROUTING")
    middleware = SubdomainRouter.new(@app)
    status, _, _ = middleware.call({ "HTTP_HOST" => "anything.com", "PATH_INFO" => "/anything" })
    assert_equal 200, status
  end

  test "/up is allowed on any host" do
    assert_allowed "app.firefight.app", "/up"
    assert_allowed "api.firefight.app", "/up"
    assert_allowed "slack.firefight.app", "/up"
    assert_allowed "firefight.app", "/up"
    assert_allowed "anything.com", "/up"
  end

  test "app subdomain allows dashboard paths" do
    assert_allowed "app.firefight.app", "/"
    assert_allowed "app.firefight.app", "/login"
    assert_allowed "app.firefight.app", "/logout"
    assert_allowed "app.firefight.app", "/app"
    assert_allowed "app.firefight.app", "/app/incidents/1"
    assert_allowed "app.firefight.app", "/auth/slack/callback"
    assert_allowed "app.firefight.app", "/rails/active_storage/blobs/abc"
    assert_allowed "app.firefight.app", "/vite/assets/app.css"
  end

  test "app subdomain blocks api and slack paths" do
    assert_blocked "app.firefight.app", "/api/v1/incidents"
    assert_blocked "app.firefight.app", "/api/v1/commands"
    assert_blocked "app.firefight.app", "/random"
  end

  test "api subdomain allows api paths" do
    assert_allowed "api.firefight.app", "/api/v1/incidents"
    assert_allowed "api.firefight.app", "/api/v1/severities"
    assert_allowed "api.firefight.app", "/api/v1/statuses"
    assert_allowed "api.firefight.app", "/api/v1/incident_types"
  end

  test "api subdomain blocks slack webhook paths" do
    assert_blocked "api.firefight.app", "/api/v1/commands"
    assert_blocked "api.firefight.app", "/api/v1/events"
    assert_blocked "api.firefight.app", "/api/v1/interactions"
  end

  test "api subdomain blocks dashboard paths" do
    assert_blocked "api.firefight.app", "/app/"
    assert_blocked "api.firefight.app", "/login"
    assert_blocked "api.firefight.app", "/"
  end

  test "slack subdomain allows only slack webhook paths" do
    assert_allowed "slack.firefight.app", "/api/v1/commands"
    assert_allowed "slack.firefight.app", "/api/v1/events"
    assert_allowed "slack.firefight.app", "/api/v1/interactions"
  end

  test "slack subdomain blocks everything else" do
    assert_blocked "slack.firefight.app", "/api/v1/incidents"
    assert_blocked "slack.firefight.app", "/app/"
    assert_blocked "slack.firefight.app", "/"
  end

  test "apex domain is blocked" do
    assert_blocked "firefight.app", "/"
    assert_blocked "firefight.app", "/anything"
  end

  test "unknown subdomains are blocked" do
    assert_blocked "typo.firefight.app", "/api/v1/incidents"
    assert_blocked "random.example.com", "/app/"
  end

  test "port is stripped from host" do
    assert_allowed "app.firefight.app:443", "/app/"
    assert_allowed "api.firefight.app:443", "/api/v1/incidents"
  end

  test "prefix boundary is enforced" do
    # /api/v1/incidents_secret should not match /api/v1/incidents
    # Both are under /api/v1 prefix so on api subdomain they'd both pass,
    # but the boundary check matters on app subdomain where /app prefix is used.
    assert_blocked "app.firefight.app", "/apple"
    assert_blocked "app.firefight.app", "/authentic"
  end
end
