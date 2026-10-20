require "test_helper"

module Integrations
  module NamedTools
    class CloudflareTest < ActiveSupport::TestCase
      ACCOUNT = "0123456789abcdef0123456789abcdef".freeze
      BUILD = "f64788e9-fccd-4d4a-a28a-cb84f88f6a1c".freeze

      test "each tool is a change, the cancel stops what someone started, and each has a plain summary" do
        entry = IntegrationProvider.find("cloudflare")

        assert_equal %w[retry_pages_deployment cancel_workers_build split_worker_traffic], Cloudflare.definitions.map(&:name)
        assert Cloudflare.definitions.none?(&:read_only)
        assert_equal [ "cancel_workers_build" ], entry.stopping_tools
        Cloudflare.definitions.each { |definition| assert_equal definition.summary, entry.tool_summaries[definition.name] }
        assert_equal Cloudflare, Provider.for("cloudflare").named_tools
      end

      test "a retry and a cancel are the one request Cloudflare's API reference gives, every value checked before it goes in the path" do
        tool, arguments = Cloudflare.call_for("cancel_workers_build", "account_id" => ACCOUNT, "build" => BUILD)

        assert_equal "execute", tool
        assert_equal ACCOUNT, arguments["account_id"]
        assert_equal({ "method" => "PUT", "path" => "/accounts/#{ACCOUNT}/builds/builds/#{BUILD}/cancel" }, request_of(arguments))
        assert ReadGuards::Cloudflare.reads?("execute", arguments) == false, "a change is never taken for a read"

        assert_match "account_id must be", assert_raises(Error) { Cloudflare.call_for("cancel_workers_build", "account_id" => "x", "build" => BUILD) }.message
        assert_match "build must be", assert_raises(Error) { Cloudflare.call_for("cancel_workers_build", "account_id" => ACCOUNT, "build" => "../zones") }.message
        _, retried = Cloudflare.call_for("retry_pages_deployment", "account_id" => ACCOUNT, "project" => "docs", "deployment" => BUILD)
        assert_equal "/accounts/#{ACCOUNT}/pages/projects/docs/deployments/#{BUILD}/retry", request_of(retried)["path"]
      end

      test "a split is a percentage deployment of two different versions whose shares add up to 100" do
        versions = [ { "version_id" => "aaaa-1", "percentage" => 10 }, { "version_id" => "bbbb-2", "percentage" => "90" } ]
        _, arguments = Cloudflare.call_for("split_worker_traffic", "account_id" => ACCOUNT, "worker" => "edge-api", "versions" => versions)

        request = request_of(arguments)
        assert_equal [ "POST", "/accounts/#{ACCOUNT}/workers/scripts/edge-api/deployments", "percentage" ], [ request["method"], request["path"], request.dig("body", "strategy") ]
        assert_equal [ { "version_id" => "aaaa-1", "percentage" => 10.0 }, { "version_id" => "bbbb-2", "percentage" => 90.0 } ], request.dig("body", "versions")
        assert_equal "Traffic split by Firefight", request.dig("body", "annotations", "workers/message")

        refused = ->(given) { assert_raises(Error) { Cloudflare.call_for("split_worker_traffic", "account_id" => ACCOUNT, "worker" => "edge-api", "versions" => given) }.message }
        assert_match "two versions", refused.call(versions.first(1))
        assert_match "add up to 100", refused.call([ versions.first, versions.second.merge("percentage" => 80) ])
        assert_match "must be different", refused.call([ versions.first.merge("percentage" => 50), versions.first.merge("percentage" => 50) ])
        assert_match "percentage must be", refused.call([ versions.first.merge("percentage" => 0), versions.second.merge("percentage" => 100) ])
      end

      test "the answer says what the call did ahead of Cloudflare's own, and a failure comes back as it was" do
        result = { "content" => [ { "type" => "text", "text" => %({"success":true}) } ] }
        said = Cloudflare.present("split_worker_traffic", { "worker" => "edge-api", "versions" => [ { "version_id" => "a", "percentage" => 10 }, { "version_id" => "b", "percentage" => 90 } ] }, result)

        assert_equal "edge-api now serves 10% to version a and 90% to version b.", said["content"].first["text"]
        cancel = ->(outcome) { { "content" => [ { "type" => "text", "text" => { "success" => true, "result" => { "build_uuid" => BUILD, "build_outcome" => outcome } }.to_json } ] } }
        words = ->(outcome) { Cloudflare.present("cancel_workers_build", { "build" => BUILD }, cancel.call(outcome))["content"].first["text"] }
        assert_equal "Workers build #{BUILD} is cancelled, so what it built is not deployed.", words.call("cancelled")
        assert_equal "Workers build #{BUILD} had already finished with outcome success, so nothing was cancelled.", words.call("success")
        assert_match "Cloudflare is cancelling Workers build #{BUILD}.", words.call(nil)

        failed = { "isError" => true, "content" => [ { "type" => "text", "text" => "boom" } ] }
        assert_equal failed, Cloudflare.present("cancel_workers_build", { "build" => BUILD }, failed)
      end

      private

      def request_of(arguments) = JSON.parse(arguments["code"][/cloudflare\.request\((\{.*?\})\);/, 1])
    end
  end
end
