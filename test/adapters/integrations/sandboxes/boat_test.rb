require "test_helper"

module Integrations
  module Sandboxes
    # The API's answers are shaped from boat.dev's OpenAPI document (docs.boat.dev/openapi/boat-v1.yaml).
    class BoatTest < ActiveSupport::TestCase
      setup do
        @api = BoatApi.new
        @boat = Boat.new(api: @api)
        @boat.stubs(:pause)
        @api.stubs(:rename)
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "provisioning" }, { "id" => "bx_23456789", "state" => "idle" })
        @api.stubs(:run_detached).returns(41)
        @api.stubs(:command_status).returns({ "status" => "running" }, { "status" => "exited", "exitCode" => 0 })
        @api.stubs(:host).returns("https://swift-otter-9021-8080.on.boat.dev?_token=gate")
        @api.stubs(:save_snapshot).returns({ "status" => "saving" })
      end

      test "a first box pulls the image, runs it with the VM's Docker and its own key, and is reached at its gated address" do
        @api.stubs(:snapshot).raises(BoatApi::NotFound, "boat.dev answered 404: Named snapshot not found. (not_found)")
        created = nil
        @api.expects(:create).with { |body, idempotency_key:| (created = body) && idempotency_key.present? }
            .returns({ "ok" => true, "type" => "sandbox.created", "sandbox" => { "id" => "bx_23456789", "state" => "provisioning" } })
        script = nil
        @api.expects(:run_detached).with { |_ref, command| script = command }.returns(41)
        @api.expects(:rename).with("bx_23456789", "halon-box-1")
        @api.expects(:save_snapshot).with("bx_23456789", regexp_matches(/\Ahalon-image-\h{16}\z/))

        box = @boat.start(name: "halon-box-1", fail_fast: true)

        assert_equal({ type: "default", ttlSeconds: Boat::TTL.to_i, noEnv: true, failFast: true }, created)
        assert_equal "https://swift-otter-9021-8080.on.boat.dev?_token=gate", box.address
        assert box.relayed
        assert_includes script, "-e SANDBOX_KEY=#{box.key}"
        assert_includes script, "-v /var/run/docker.sock:/var/run/docker.sock"
        assert_includes script, "-v halon-runs:/runs"
        assert_includes script, Sandboxes.image
      end

      test "a later box starts from the image's own copy, and one for a prepared repository from that copy" do
        @api.stubs(:snapshot).returns({ "name" => "halon-image-x", "status" => "ready" })
        froms = []
        @api.stubs(:create).with { |body, **| froms << body[:from] }.returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:save_snapshot).never

        @boat.start(name: "halon-box-1")
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "ready" })
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 0 })
        @boat.start(name: "halon-box-2", from: "halon-kept-abc")

        assert_match(/\Ahalon-image-\h{16}\z/, froms.first)
        assert_equal "halon-kept-abc", froms.last
      end

      test "a sandbox that will not start, or an image that will not run, is deleted and said in boat's words" do
        @api.stubs(:snapshot).raises(BoatApi::NotFound, "gone")
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "error", "error" => "Provisioning failed." })
        @api.expects(:delete).with("bx_23456789")

        error = assert_raises(Error) { @boat.start(name: "halon-box-1") }
        assert_equal "boat.dev could not start the sandbox: Provisioning failed.", error.message

        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "idle" })
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 125, "stderr" => "docker: manifest unknown.\n" })
        @api.expects(:delete).with("bx_23456789")
        refused = assert_raises(Error) { @boat.start(name: "halon-box-1") }
        assert_equal "The sandbox image did not start on boat.dev: docker: manifest unknown.", refused.message
      end

      test "stopping archives the box, and tidying deletes it later with copies nothing names" do
        @api.expects(:stop).with("bx_23456789")
        @boat.stop("bx_23456789")

        @api.stubs(:sandboxes).returns([
          { "id" => "bx_old", "name" => "halon-box-1", "state" => "archived", "updatedAt" => 2.hours.ago.iso8601 },
          { "id" => "bx_new", "name" => "halon-box-2", "state" => "archived", "updatedAt" => 5.minutes.ago.iso8601 },
          { "id" => "bx_mine", "name" => "My sandbox", "state" => "archived", "updatedAt" => 2.days.ago.iso8601 }
        ])
        @api.stubs(:snapshots).returns([
          { "name" => "halon-kept-known", "status" => "ready", "createdAt" => 2.days.ago.iso8601 },
          { "name" => "halon-kept-lost", "status" => "ready", "createdAt" => 2.days.ago.iso8601 },
          { "name" => "halon-kept-saving", "status" => "saving", "createdAt" => 1.minute.ago.iso8601 },
          { "name" => "halon-image-0000000000000000", "status" => "ready", "createdAt" => 1.hour.ago.iso8601 },
          { "name" => "web-stack", "status" => "ready", "createdAt" => 9.days.ago.iso8601 }
        ])
        @api.expects(:delete).with("bx_old").once
        @api.expects(:delete_snapshot).with("halon-kept-lost").once
        @api.expects(:delete_snapshot).with("halon-image-0000000000000000").once

        @boat.tidy(kept_refs: Set["halon-kept-known"])
      end

      test "only running boxes named like a box are listed, so the sweep never touches the account's own" do
        @api.stubs(:sandboxes).returns([
          { "id" => "bx_1", "name" => "halon-box-1", "state" => "idle", "createdAt" => "2026-10-09T10:00:00Z" },
          { "id" => "bx_2", "name" => "halon-box-2", "state" => "archived", "createdAt" => "2026-10-09T10:00:00Z" },
          { "id" => "bx_3", "name" => "Sandbox 2026-10-09", "state" => "running", "createdAt" => "2026-10-09T10:00:00Z" }
        ])

        assert_equal [ "bx_1" ], @boat.running.map(&:ref)
      end

      test "what boat holds for Firefight is listed with its state in one vocabulary, and copies past the free ten carry a price" do
        @api.stubs(:sandboxes).returns([
          { "id" => "bx_1", "name" => "halon-box-1", "state" => "idle", "type" => "default", "createdAt" => "2026-10-09T10:00:00Z" },
          { "id" => "bx_2", "name" => "halon-box-2", "state" => "error", "type" => "default", "createdAt" => "2026-10-09T10:00:00Z" },
          { "id" => "bx_3", "name" => "My sandbox", "state" => "running", "createdAt" => "2026-10-09T10:00:00Z" }
        ])
        others = (1..10).map { |index| { "name" => "web-stack-#{index}", "status" => "ready", "createdAt" => index.hours.ago.iso8601 } }
        @api.stubs(:snapshots).returns(others + [
          { "name" => "halon-kept-old", "status" => "ready", "sizeBytes" => 2_000_000_000, "createdAt" => 2.days.ago.iso8601 },
          { "name" => "halon-image-0123456789abcdef", "status" => "saving", "createdAt" => 1.minute.ago.iso8601 }
        ])

        held = @boat.inventory.index_by(&:ref)

        assert_equal %w[bx_1 bx_2 halon-image-0123456789abcdef halon-kept-old].sort, held.keys.sort, "only what is named like Firefight's"
        assert_equal ProviderSandbox::PHASE_RUNNING, held["bx_1"].phase
        assert_equal ProviderSandbox::PHASE_FAILED, held["bx_2"].phase
        assert_equal [ ProviderSandbox::PURPOSE_PREPARED, ProviderSandbox::PHASE_READY, Boat::SNAPSHOT_MONTHLY_MICROS, 2_000_000_000 ],
                     held["halon-kept-old"].then { |copy| [ copy.purpose, copy.phase, copy.monthly_micros, copy.byte_size ] }
        assert_equal [ ProviderSandbox::PURPOSE_IMAGE, ProviderSandbox::PHASE_STARTING, 0 ],
                     held["halon-image-0123456789abcdef"].then { |copy| [ copy.purpose, copy.phase, copy.monthly_micros ] }
      end

      test "a box is priced by its size, from boat's list prices" do
        ENV.stubs(:[]).with(anything).returns(nil)
        ENV.stubs(:[]).with("BOAT_SANDBOX_TYPE").returns("large")

        assert_equal "large", @boat.size
        assert_equal 72_000, @boat.hourly_micros
      end
    end
  end
end
