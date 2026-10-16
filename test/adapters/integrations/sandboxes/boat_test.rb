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
        assert_equal({ "_token" => "_port_auth" }, box.cookies, "boat answers _token with a redirect, so it travels as the cookie that redirect would set")
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

      test "of boxes that start at once for a new image, exactly one saves its copy, and every box is handed back" do
        no_copy!
        @api.stubs(:create).returns(*Array.new(5) { |index| { "sandbox" => { "id" => "bx_#{index}" } } })
        saved = Queue.new
        @api.stubs(:save_snapshot).with { |ref, _name| saved << ref }.returns({ "status" => "saving" })
        @api.expects(:delete).never

        boxes = Array.new(5) { |index| Thread.new { @boat.start(name: "halon-box-#{index}") } }.map(&:value)

        assert_equal 5, boxes.map(&:ref).uniq.size
        assert_equal 1, saved.size
        claim = SandboxImageCopy.find_by!(provider: SandboxProviders::BOAT, name: image_copy_name)
        assert_equal [ SandboxImageCopy::STATUS_SAVING, saved.pop ], [ claim.status, claim.claimed_by ]
      end

      test "a first pull that takes minutes is followed to the end, the box comes up and its copy is saved, and the client then waits only for it to answer" do
        no_copy!
        seconds = 0
        @boat.define_singleton_method(:clock) { seconds += 60 }
        @api.stubs(:command_status).returns(*Array.new(6) { { "status" => "running" } }, { "status" => "exited", "exitCode" => 0 })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_slow" } })
        @api.expects(:save_snapshot).with("bx_slow", image_copy_name).returns({ "status" => "saving" })
        @api.expects(:delete).never

        assert_equal "bx_slow", @boat.start(name: "halon-box-1").ref
        assert_operator seconds, :>, Client::READY_TIMEOUT
        assert_equal Client::READY_TIMEOUT, @boat.ready_within
      end

      test "the image copy is prepared ahead of need by one claimant per version, in a box archived once the save is asked for" do
        no_copy!
        @api.expects(:create).once.returns({ "sandbox" => { "id" => "bx_prepare" } })
        @api.expects(:save_snapshot).once.with("bx_prepare", image_copy_name).returns({ "status" => "saving" })
        @api.expects(:stop).once.with("bx_prepare")

        2.times { @boat.prepare_image! }

        assert_match(/\Aprepare-/, SandboxImageCopy.find_by!(provider: SandboxProviders::BOAT, name: image_copy_name).claimed_by)
      end

      test "a copy boat already has, or is saving, is not prepared again, and a prepare that fails lets the claim go" do
        @api.stubs(:snapshot).returns({ "name" => image_copy_name, "status" => "ready" })
        @api.expects(:create).never
        @boat.prepare_image!
        @api.stubs(:snapshot).returns({ "name" => image_copy_name, "status" => "saving" })
        @boat.prepare_image!

        no_copy!
        @api.unstub(:create)
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_prepare" } })
        @api.stubs(:sandbox).returns({ "id" => "bx_prepare", "state" => "error", "error" => "Provisioning failed." })
        @api.expects(:delete).with("bx_prepare")
        Rails.logger.stubs(:warn)

        @boat.prepare_image!

        assert_equal SandboxImageCopy::STATUS_FAILED, SandboxImageCopy.find_by!(provider: SandboxProviders::BOAT, name: image_copy_name).status
      end

      test "a refused save leaves the box running, is logged, and lets a later box claim the save again" do
        no_copy!
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_first" } }, { "sandbox" => { "id" => "bx_later" } })
        @api.expects(:save_snapshot).with("bx_first", image_copy_name)
            .raises(BoatApi::Error, 'boat.dev answered 409: "halon-image-5160fe96712a73cc" is already being saved. Wait for it to finish. (save_in_progress)')
        @api.expects(:delete).never
        Rails.logger.stubs(:warn)
        Rails.logger.expects(:warn).with { |line| line.include?("code_box.image_copy_failed") && line.include?("save_in_progress") }

        assert_equal "bx_first", @boat.start(name: "halon-box-1").ref
        assert_equal SandboxImageCopy::STATUS_FAILED, SandboxImageCopy.find_by!(provider: SandboxProviders::BOAT, name: image_copy_name).status

        @api.expects(:save_snapshot).with("bx_later", image_copy_name).returns({ "status" => "saving" })
        @boat.start(name: "halon-box-2")
      end

      test "a claim held by a box still saving is left to it, and one abandoned is taken over" do
        no_copy!
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_new" } })
        claim = SandboxImageCopy.create!(provider: SandboxProviders::BOAT, name: image_copy_name, status: SandboxImageCopy::STATUS_SAVING,
                                         claimed_by: "bx_other", claimed_at: 1.minute.ago)
        @api.expects(:save_snapshot).never
        @boat.start(name: "halon-box-1")

        claim.update!(claimed_at: (SandboxImageCopy::ABANDONED_AFTER + 1.minute).ago)
        @api.expects(:save_snapshot).with("bx_new", image_copy_name).returns({ "status" => "saving" })
        @boat.start(name: "halon-box-2")

        assert_equal "bx_new", claim.reload.claimed_by
      end

      test "a copy boat has ready is marked ready, and claimed again once boat no longer holds it" do
        @api.stubs(:snapshot).returns({ "name" => image_copy_name, "status" => "ready" })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        SandboxImageCopy.create!(provider: SandboxProviders::BOAT, name: image_copy_name, status: SandboxImageCopy::STATUS_SAVING,
                                 claimed_by: "bx_other", claimed_at: 1.minute.ago)
        @boat.start(name: "halon-box-1")
        assert_equal SandboxImageCopy::STATUS_READY, SandboxImageCopy.find_by!(provider: SandboxProviders::BOAT, name: image_copy_name).status

        no_copy!
        @api.expects(:save_snapshot).with("bx_23456789", image_copy_name).returns({ "status" => "saving" })
        @boat.start(name: "halon-box-2")
      end

      test "a box started while the image copy is being saved pulls the image and leaves the saving to the box already at it" do
        @api.stubs(:snapshot).returns({ "name" => "halon-image-x", "status" => "saving" })
        created = nil
        @api.expects(:create).with { |body, **| created = body }.returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:save_snapshot).never

        @boat.start(name: "halon-box-1")

        assert_nil created[:from]
      end

      test "a failed image copy is deleted so the next box can save it again under its name" do
        @api.stubs(:snapshot).returns({ "name" => "halon-image-x", "status" => "failed" })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        saving = sequence("saving")
        @api.expects(:delete_snapshot).with(regexp_matches(/\Ahalon-image-\h{16}\z/)).in_sequence(saving)
        @api.expects(:save_snapshot).with("bx_23456789", regexp_matches(/\Ahalon-image-\h{16}\z/)).in_sequence(saving)

        @boat.start(name: "halon-box-1")
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

        SandboxImageCopy.create!(provider: SandboxProviders::BOAT, name: "halon-image-0000000000000000", status: SandboxImageCopy::STATUS_READY)
        SandboxImageCopy.create!(provider: SandboxProviders::BOAT, name: image_copy_name, status: SandboxImageCopy::STATUS_READY)

        @boat.tidy(kept_refs: Set["halon-kept-known"])

        assert_equal [ image_copy_name ], SandboxImageCopy.where(provider: SandboxProviders::BOAT).pluck(:name), "only the claim on the image run now is kept"
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
        assert_equal 200_000, @boat.hourly_micros_for("xlarge")
      end

      test "a box is named for the workspace and run it was started for, and the name is read back" do
        owner = Owner.new(workspace_id: "0b6f6c1e-58d4-4a8e-9a43-1f1f2b0c9d11", key: "investigation-5d1e2f30-9c4b-4d0e-8f7a-2b3c4d5e6f70")
        @api.stubs(:snapshot).returns({ "status" => "ready" })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:rename).with("bx_23456789", "halon-box-#{owner.workspace_id}-#{owner.key}")

        @boat.start(name: "halon-box-1", owner: owner)

        @api.stubs(:snapshots).returns([])
        @api.stubs(:sandboxes).returns([
          { "id" => "bx_owned", "name" => "halon-box-#{owner.workspace_id}-#{owner.key}", "state" => "idle" },
          { "id" => "bx_older", "name" => "halon-box-1", "state" => "idle" }
        ])
        held = @boat.inventory.index_by(&:ref)
        assert_equal owner, held["bx_owned"].owner
        assert_nil held["bx_older"].owner, "a box from before boxes carried their owner says nothing"
      end

      test "a name that would not fit goes without its owner rather than being cut" do
        owner = Owner.new(workspace_id: "0b6f6c1e-58d4-4a8e-9a43-1f1f2b0c9d11", key: "mcp-#{'x' * 80}")
        @api.stubs(:snapshot).returns({ "status" => "ready" })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:rename).with("bx_23456789", "halon-box-1")

        @boat.start(name: "halon-box-1", owner: owner)
      end

      test "a box is handed back by starting its image again with a key the app knows, keeping its volumes" do
        script = nil
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 0 })
        @api.expects(:run_detached).with { |ref, command| ref == "bx_lost" && (script = command) }.returns(41)
        @api.expects(:create).never

        box = @boat.reclaim("bx_lost")

        assert_equal [ "bx_lost", "https://swift-otter-9021-8080.on.boat.dev?_token=gate", true ], [ box.ref, box.address, box.relayed ]
        assert_includes script, "-e SANDBOX_KEY=#{box.key}"
        assert_includes script, "-v halon-code:/code"
      end

      private

      def image_copy_name = "halon-image-#{Digest::SHA256.hexdigest(Sandboxes.image)[0, 16]}"

      def no_copy!
        @api.stubs(:snapshot).raises(BoatApi::NotFound, "boat.dev answered 404: Named snapshot not found. (not_found)")
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "idle" })
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 0 })
      end
    end
  end
end
