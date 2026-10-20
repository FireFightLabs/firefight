require "test_helper"

module Integrations
  class NeonApiTest < ActiveSupport::TestCase
    KEY = "Bearer napi_example".freeze

    setup do
      @api = NeonApi.new(KEY)
    end

    test "a branch is restored with a POST of the restore body, with the key as it is held" do
      body = { "source_branch_id" => "br-main-1", "source_timestamp" => "2026-10-20T14:30:00Z", "preserve_under_name" => "main-before-rollback-10201500" }
      Http.expects(:request).with do |uri, request, **|
        uri.to_s == "https://console.neon.tech/api/v2/projects/shop-123/branches/br-main-1/restore" && request.is_a?(Net::HTTP::Post) &&
          request["Authorization"] == KEY && JSON.parse(request.body) == body && request["Content-Type"] == "application/json"
      end.returns(response(200, { branch: { id: "br-main-1" }, operations: [] }))

      assert_equal({ "branch" => { "id" => "br-main-1" }, "operations" => [] }, @api.restore_branch("shop-123", "br-main-1", body))
    end

    test "consumption is read for one project of an organization, with every query parameter the API requires" do
      Http.expects(:request).with do |uri, request, **|
        uri.path == "/api/v2/consumption_history/v2/projects" && request.is_a?(Net::HTTP::Get) &&
          URI.decode_www_form(uri.query).to_h == { "org_id" => "org-1", "project_ids" => "shop-123", "from" => "2026-10-20T00:00:00Z",
                                                   "to" => "2026-10-20T12:00:00Z", "granularity" => "hourly",
                                                   "metrics" => "compute_unit_seconds,public_network_transfer_bytes" }
      end.returns(response(200, { projects: [ { project_id: "other" }, { project_id: "shop-123", periods: [] } ] }))

      found = @api.consumption(org_id: "org-1", project_id: "shop-123", from: "2026-10-20T00:00:00Z", to: "2026-10-20T12:00:00Z", granularity: "hourly",
                               metrics: %w[compute_unit_seconds public_network_transfer_bytes])
      assert_equal({ "project_id" => "shop-123", "periods" => [] }, found)
    end

    test "a refused key is told apart from another failure" do
      Http.expects(:request).returns(response(403, { message: "Not available for this account" }))
      error = assert_raises(NeonApi::Refused) { @api.project("shop-123") }
      assert_match "Not available for this account", error.message

      Http.expects(:request).returns(response(500, { message: "boom" }))
      assert_not_kind_of NeonApi::Refused, assert_raises(NeonApi::Error) { @api.project("shop-123") }
    end

    private

    def response(code, body)
      stub(code: code.to_s, body: body.to_json, each_header: [].each, to_hash: {})
    end
  end
end
