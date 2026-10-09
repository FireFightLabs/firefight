require "test_helper"

module Integrations
  # Answers are shaped from boat.dev's OpenAPI document (docs.boat.dev/openapi/boat-v1.yaml) and its error model.
  class BoatApiTest < ActiveSupport::TestCase
    setup do
      ENV.stubs(:[]).with(anything).returns(nil)
      ENV.stubs(:[]).with("BOAT_API_KEY").returns("sandbox_secret")
      @api = BoatApi.new
    end

    test "a sandbox is created with the deployment's key and an idempotency key, so a retry never bills a second one" do
      sent = expect_request(202, { "ok" => true, "type" => "sandbox.created", "status" => "provisioning", "ttlSeconds" => 21_600,
                                   "sandbox" => { "id" => "bx_23456789", "state" => "provisioning", "desktopAvailable" => false, "snapshotAvailable" => false } })

      created = @api.create({ type: "default", noEnv: true }, idempotency_key: "6f9619ff-8b86-d011-b42d-00cf4fc964ff")

      uri, request = sent.call
      assert_equal "https://boat.dev/api/v1/sandboxes", uri.to_s
      assert_equal "Bearer sandbox_secret", request["Authorization"]
      assert_equal "6f9619ff-8b86-d011-b42d-00cf4fc964ff", request["Idempotency-Key"]
      assert_equal({ "type" => "default", "noEnv" => true }, JSON.parse(request.body))
      assert_equal "bx_23456789", created.dig("sandbox", "id")
    end

    test "a delete names its target again, as boat asks" do
      sent = expect_request(202, { "ok" => true, "type" => "deletion.accepted", "operation" => { "id" => "op_1", "status" => "accepted" } })

      @api.delete("bx_23456789")

      uri, request = sent.call
      assert_equal "/api/v1/sandboxes/bx_23456789", uri.path
      assert_equal "bx_23456789", request["X-Ascii-Confirm-Delete"]
    end

    test "a refusal is raised in boat's own words as the class its status names" do
      Http.stubs(:request).returns(response(503, { "ok" => false, "type" => "sandbox.error", "status" => 503, "code" => "no_ready_machine",
                                                   "message" => "No machine of this type is ready.", "requestId" => "req_1" }))
      no_machine = assert_raises(BoatApi::NoCapacity) { @api.create({ failFast: true }, idempotency_key: "k") }
      assert_equal "boat.dev answered 503: No machine of this type is ready. (no_ready_machine)", no_machine.message
      assert_kind_of Sandboxes::Error, no_machine, "every refusal fails over like any box that cannot start"

      Http.stubs(:request).returns(response(401, { "ok" => false, "code" => "unauthorized", "message" => "Provide a valid bearer token." }))
      assert_raises(BoatApi::Unauthorized) { @api.sandbox("bx_23456789") }

      Http.stubs(:request).returns(response(404, { "ok" => false, "code" => "not_found", "message" => "not_found" }))
      gone = assert_raises(BoatApi::NotFound) { @api.sandbox("bx_23456789") }
      assert_kind_of Integrations::NotFound, gone
      assert_equal "boat.dev answered 404: not_found", gone.message, "a message that is only the code is said once, as boat answers a missing snapshot"

      Http.stubs(:request).returns(response(402, { "ok" => false, "code" => "billing_required", "message" => "Start the $20/month Boat plan to create sandboxes." }))
      unpaid = assert_raises(BoatApi::Error) { @api.create({}, idempotency_key: "k") }
      assert_kind_of Sandboxes::Error, unpaid, "an account that cannot create sandboxes fails over like any refusal"
    end

    test "every page of sandboxes is read" do
      Http.stubs(:request).returns(
        response(200, { "ok" => true, "type" => "sandbox.list", "sandboxes" => [ { "id" => "bx_aaaaaaaa", "name" => "halon-box-1" } ],
                        "pageInfo" => { "nextCursor" => "c2", "hasMore" => true, "limit" => 100 } }),
        response(200, { "ok" => true, "type" => "sandbox.list", "sandboxes" => [ { "id" => "bx_bbbbbbbb", "name" => "halon-box-2" } ],
                        "pageInfo" => { "nextCursor" => nil, "hasMore" => false, "limit" => 100 } })
      )

      assert_equal %w[bx_aaaaaaaa bx_bbbbbbbb], @api.sandboxes.map { |sandbox| sandbox["id"] }
    end

    test "a wallet named by BOAT_ORG is what every request bills" do
      ENV.stubs(:[]).with("BOAT_ORG").returns("team_firefight")
      sent = expect_request(200, { "ok" => true, "type" => "snapshot.named.list", "snapshots" => [] })

      @api.snapshots

      assert_equal "team_firefight", sent.call.last["X-Boat-Org"]
    end

    test "without a key it says which setting is missing" do
      ENV.stubs(:[]).with("BOAT_API_KEY").returns(nil)

      error = assert_raises(BoatApi::Error) { @api.sandbox("bx_23456789") }
      assert_equal "BOAT_API_KEY is not set.", error.message
    end

    private

    def expect_request(code, body)
      sent = nil
      Http.expects(:request).with do |uri, request, **|
        sent = [ uri, request ]
        true
      end.returns(response(code, body))
      -> { sent }
    end

    def response(code, body) = stub(code: code.to_s, body: body.to_json)
  end
end
