require "test_helper"

module Integrations
  # Paths and bodies as Jira Cloud's REST API v3 and Atlassian's OAuth 2.0 gateway document them.
  class JiraApiTest < ActiveSupport::TestCase
    def capture(*answers)
      sent = []
      Http.stubs(:json).with { |uri, request, **| sent << [ request.method, uri.to_s, request.body && JSON.parse(request.body) ] }.returns(*answers)
      sent
    end

    def api = JiraApi.new("Authorization" => "Bearer atl_oauth")

    RESOURCES = [ { "id" => "cloud-1", "url" => "https://acme.atlassian.net", "name" => "acme" } ].freeze

    test "a site's cloud id comes from the token's accessible resources, and a site it does not reach is refused" do
      capture(RESOURCES)

      assert_equal "cloud-1", api.cloud_id("acme.atlassian.net")
      assert_raises(JiraApi::Error) { api.cloud_id("other.atlassian.net") }
    end

    test "issue calls go through the gateway to the site's REST API" do
      sent = capture({ "key" => "OPS-1" }, {})

      api.create_issue("cloud-1", { "summary" => "x" })
      api.edit_issue("cloud-1", "OPS-1", { "assignee" => nil })

      assert_equal [ "POST", "https://api.atlassian.com/ex/jira/cloud-1/rest/api/3/issue", { "fields" => { "summary" => "x" } } ], sent.first
      assert_equal [ "PUT", "https://api.atlassian.com/ex/jira/cloud-1/rest/api/3/issue/OPS-1", { "fields" => { "assignee" => nil } } ], sent.last
    end

    test "a webhook is registered for updated and deleted issues the JQL matches, refreshed and deleted by its id" do
      sent = capture({ "webhookRegistrationResult" => [ { "createdWebhookId" => 1000 } ] }, { "expirationDate" => "2026-11-04T10:00:00.000+0000" }, {})

      assert_equal 1000, api.register_webhook("cloud-1", "https://ff.example.com/hook", 'project = "OPS"')
      assert_equal "2026-11-04T10:00:00.000+0000", api.refresh_webhook("cloud-1", "1000")
      api.delete_webhook("cloud-1", "1000")

      assert_equal({ "url" => "https://ff.example.com/hook",
                     "webhooks" => [ { "events" => %w[jira:issue_updated jira:issue_deleted], "jqlFilter" => 'project = "OPS"' } ] }, sent[0].last)
      assert_equal [ "PUT", "https://api.atlassian.com/ex/jira/cloud-1/rest/api/3/webhook/refresh", { "webhookIds" => [ 1000 ] } ], sent[1]
      assert_equal [ "DELETE", "https://api.atlassian.com/ex/jira/cloud-1/rest/api/3/webhook", { "webhookIds" => [ 1000 ] } ], sent[2]
    end

    test "a registration Jira refuses says why" do
      capture({ "webhookRegistrationResult" => [ { "errors" => [ "Invalid JQL" ] } ] })

      error = assert_raises(JiraApi::Error) { api.register_webhook("cloud-1", "https://ff.example.com/hook", "x") }
      assert_equal "Invalid JQL", error.message
    end
  end
end
