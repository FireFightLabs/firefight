require "test_helper"

module Integrations
  class ApiReadsTest < ActiveSupport::TestCase
    test "a path stays a plain path of the API, with a leading slash, and never climbs out of it" do
      assert_equal "/services/srv-1/deploys", ApiReads.path!("services/srv-1/deploys/")
      assert_equal "/v1/apps/web", ApiReads.path!(" /v1/apps/web ")
      assert_equal "/repositories/acme/web/pipelines/%7Babc-1%7D", ApiReads.path!("/repositories/acme/web/pipelines/{abc-1}")

      [ "/services/../owners", "/services/%2e%2e", "/services?limit=5", "/a//b", "https://evil.example.com/x", "/a#b", "" ].each do |path|
        assert_raises(ReadGuards::Refused, path) { ApiReads.path!(path) }
      end
    end

    test "query parameters are names and plain values, a list sent once per value" do
      assert_equal({ "limit" => "20", "ok" => "true", "status" => %w[live failed] }, ApiReads.query!("limit" => 20, "ok" => true, "status" => %w[live failed]))
      assert_equal "GET /services?limit=20&status=live&status=failed", ApiReads.asked("/services", "limit" => "20", "status" => %w[live failed])

      assert_raises(ReadGuards::Refused) { ApiReads.query!("limit=1&x" => 1) }
      assert_raises(ReadGuards::Refused) { ApiReads.query!("filter" => { "a" => 1 }) }
      assert_raises(ReadGuards::Refused) { ApiReads.query!("q" => "a\nb") }
      assert_raises(ReadGuards::Refused) { ApiReads.query!([ "limit" ]) }
    end

    test "secret values never come back, while their names, ids and a page's token stay readable" do
      said = {
        "id" => "srv-1", "nextPageToken" => "page-2",
        "envVars" => [ { "key" => "DATABASE_URL", "value" => "postgres://app:hunter2@db:5432/app" } ],
        "env" => [ { "name" => "STRIPE_KEY", "value" => "sk_live_abc" } ],
        "settings" => { "apiKey" => "abc123", "region" => "oregon", "webhook_secret" => "whsec" },
        "variables" => { "TOKEN" => "xyz" }
      }

      text = ApiReads.answer("Render", "GET /services/srv-1", said)

      assert text.start_with?("Render answered GET /services/srv-1.\n")
      %w[DATABASE_URL STRIPE_KEY TOKEN srv-1 page-2 oregon].each { |kept| assert_includes text, kept }
      %w[hunter2 sk_live_abc abc123 whsec xyz].each { |hidden| assert_not_includes text, hidden }
    end

    test "an answer the guard says is all secrets keeps only names, and a long answer is cut with a line saying so" do
      text = ApiReads.answer("Render", "GET /services/srv-1/env-vars", [ { "envVar" => { "key" => "PORT", "value" => "8080" } } ], secret: true)

      assert_includes text, "PORT"
      assert_not_includes text, "8080"

      long = ApiReads.answer("Render", "GET /services", [ { "name" => "x" * (ApiReads::RESULT_LIMIT + 10) } ])
      assert_match "[Cut at #{ApiReads::RESULT_LIMIT} characters.", long
    end

    test "a read outside the scopes a connection was made for is named, and a connection made for all reaches any" do
      integration = Integration.create!(workspace: workspaces(:slack_workspace_one), kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
      row = integration.integration_environments.create!
      row.store_fields!("workspace" => %w[tea-a])
      settings = ConnectionSettings.of(row)

      assert_nil ApiReads.outside_scopes(settings, [ "tea-a", nil ], "workspaces")
      assert_match "and the read reaches tea-b", ApiReads.outside_scopes(settings, %w[tea-a tea-b], "workspaces")

      row.store_fields!("workspace" => [ IntegrationProvider::ConnectField::ALL ])
      assert_nil ApiReads.outside_scopes(ConnectionSettings.of(row), %w[tea-b], "workspaces")
    end
  end
end
