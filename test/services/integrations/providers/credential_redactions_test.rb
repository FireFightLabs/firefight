require "test_helper"

module Integrations
  module Providers
    class CredentialRedactionsTest < ActiveSupport::TestCase
      TINYBIRD_TOKEN = "p.eyJ1IjogIjdmOTIwMmMzIiwgImlkIjogImZlNGQ1YWJlIn0.fEYYn4jM7fdOcj1J8z8lLcU6Ta54d3w0ULYB4_l3cO0".freeze

      test "an Upstash database or QStash answered with its credentials reaches nobody with them" do
        database = { "database_id" => "db-1", "database_name" => "cache", "endpoint" => "usw1-cache.upstash.io", "password" => "AYa1secret",
                     "rest_token" => "AYa1ASQgrest", "read_only_rest_token" => "AoOreadonly" }
        qstash = { "id" => "q-1", "token" => "eyJVc2VySUQiOiJxIn0=", "read_only_token" => "eyJyZWFkIn0=",
                   "current_signing_key" => "sig_current", "next_signing_key" => "sig_next" }
        result = { "content" => [ { "type" => "text", "text" => database.to_json }, { "type" => "text", "text" => qstash.to_json } ] }

        kept = Redactions.apply(result, **Redactions.rules("upstash"))["content"].map { |part| JSON.parse(part["text"]) }

        assert_equal "cache", kept[0]["database_name"]
        assert_equal "usw1-cache.upstash.io", kept[0]["endpoint"]
        %w[password rest_token read_only_rest_token].each { |field| assert_equal Redactions::REMOVED, kept[0][field], field }
        %w[token read_only_token current_signing_key next_signing_key].each { |field| assert_equal Redactions::REMOVED, kept[1][field], field }
      end

      test "a Tinybird token in any answer, a request address among them, is replaced" do
        result = { "content" => [ { "type" => "text", "text" => "GET /v0/pipes/top.json?date=1&token=#{TINYBIRD_TOKEN} 200" } ] }

        text = Redactions.apply(result, **Redactions.rules("tinybird"))["content"].first["text"]

        assert_not_includes text, "fEYYn4jM7fdOcj1J8z8lLcU6Ta54d3w0ULYB4_l3cO0"
        assert_includes text, "/v0/pipes/top.json?date=1&token=[REDACTED:tinybird_token] 200"
      end
    end
  end
end
