require "test_helper"

module Integrations
  module Sandboxes
    # The API's answers are shaped from boat.dev's OpenAPI document (docs.boat.dev/openapi/boat-v1.yaml).
    class BoatTest < ActiveSupport::TestCase
      OWNER = Owner.new(workspace_id: "0b6f6c1e-58d4-4a8e-9a43-1f1f2b0c9d11", key: "investigation-1")

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
        @api.expects(:save_snapshot).never

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

      test "a later box starts from its workspace's copy, and one for a prepared repository from that copy" do
        @api.stubs(:snapshot).returns({ "name" => copy_for(OWNER), "status" => "ready" })
        froms = []
        @api.stubs(:create).with { |body, **| froms << body[:from] }.returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:save_snapshot).never

        @boat.start(name: "halon-box-1", owner: OWNER)
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "ready" })
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 0 })
        @boat.start(name: "halon-box-2", owner: OWNER, from: "halon-kept-abc")

        assert_equal [ copy_for(OWNER), "halon-kept-abc" ], froms
      end

      test "of claims that prepare one workspace's copy at once, exactly one saves it" do
        no_copy!
        @api.stubs(:create).returns(*Array.new(5) { |index| { "sandbox" => { "id" => "bx_#{index}" } } })
        saved = Queue.new
        @api.stubs(:save_snapshot).with { |ref, _name| saved << ref }.returns({ "status" => "saving" })
        @api.stubs(:stop)

        Array.new(5) { Thread.new { @boat.prepare_image!(OWNER.workspace_id) } }.each(&:join)

        assert_equal 1, saved.size
        assert_equal SandboxImageCopy::STATUS_SAVING, SandboxImageCopy.find_by!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER)).status
      end

      test "a first pull that takes minutes is followed to the end, the box comes up, and the client then waits only for it to answer" do
        no_copy!
        seconds = 0
        @boat.define_singleton_method(:clock) { seconds += 60 }
        @api.stubs(:command_status).returns(*Array.new(6) { { "status" => "running" } }, { "status" => "exited", "exitCode" => 0 })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_slow" } })
        @api.expects(:save_snapshot).never
        @api.expects(:delete).never

        assert_equal "bx_slow", @boat.start(name: "halon-box-1", owner: OWNER).ref
        assert_operator seconds, :>, Client::READY_TIMEOUT
        assert_equal Client::READY_TIMEOUT, @boat.ready_within
      end

      test "the image copy is prepared ahead of need by one claimant per version and workspace, in a box archived once the save is asked for" do
        no_copy!
        @api.expects(:create).once.returns({ "sandbox" => { "id" => "bx_prepare" } })
        @api.expects(:save_snapshot).once.with("bx_prepare", copy_for(OWNER)).returns({ "status" => "saving" })
        @api.expects(:stop).once.with("bx_prepare")

        2.times { @boat.prepare_image!(OWNER.workspace_id) }

        assert_match(/\Aprepare-/, SandboxImageCopy.find_by!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER)).claimed_by)
      end

      test "a copy boat already has, or is saving, is not prepared again, and a prepare that fails lets the claim go" do
        @api.stubs(:snapshot).returns({ "name" => copy_for(OWNER), "status" => "ready" })
        @api.expects(:create).never
        @boat.prepare_image!(OWNER.workspace_id)
        @api.stubs(:snapshot).returns({ "name" => copy_for(OWNER), "status" => "saving" })
        @boat.prepare_image!(OWNER.workspace_id)

        no_copy!
        @api.unstub(:create)
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_prepare" } })
        @api.stubs(:sandbox).returns({ "id" => "bx_prepare", "state" => "error", "error" => "Provisioning failed." })
        @api.expects(:delete).with("bx_prepare")
        Rails.logger.stubs(:warn)

        @boat.prepare_image!(OWNER.workspace_id)

        assert_equal SandboxImageCopy::STATUS_FAILED, SandboxImageCopy.find_by!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER)).status
      end

      test "a refused save is logged and lets a later prepare claim the save again" do
        no_copy!
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_first" } }, { "sandbox" => { "id" => "bx_later" } })
        @api.stubs(:stop)
        @api.expects(:save_snapshot).with("bx_first", copy_for(OWNER))
            .raises(BoatApi::Error, 'boat.dev answered 409: "halon-image-5160fe96712a73cc" is already being saved. Wait for it to finish. (save_in_progress)')
        Rails.logger.stubs(:warn)
        Rails.logger.expects(:warn).with { |line| line.include?("code_box.image_copy_failed") && line.include?("save_in_progress") }

        @boat.prepare_image!(OWNER.workspace_id)
        assert_equal SandboxImageCopy::STATUS_FAILED, SandboxImageCopy.find_by!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER)).status

        @api.expects(:save_snapshot).with("bx_later", copy_for(OWNER)).returns({ "status" => "saving" })
        @boat.prepare_image!(OWNER.workspace_id)
      end

      test "a claim held by a prepare still saving is left to it, and one abandoned is taken over" do
        no_copy!
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_new" } })
        @api.stubs(:stop)
        claim = SandboxImageCopy.create!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER), status: SandboxImageCopy::STATUS_SAVING,
                                         claimed_by: "prepare-other", claimed_at: 1.minute.ago)
        @api.expects(:save_snapshot).never
        @boat.prepare_image!(OWNER.workspace_id)

        claim.update!(claimed_at: (SandboxImageCopy::ABANDONED_AFTER + 1.minute).ago)
        @api.expects(:save_snapshot).with("bx_new", copy_for(OWNER)).returns({ "status" => "saving" })
        @boat.prepare_image!(OWNER.workspace_id)

        assert_match(/\Aprepare-/, claim.reload.claimed_by)
      end

      test "a copy boat has ready is marked ready by a box that starts from it, and prepared again once boat no longer holds it" do
        @api.stubs(:snapshot).returns({ "name" => copy_for(OWNER), "status" => "ready" })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.stubs(:stop)
        SandboxImageCopy.create!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER), status: SandboxImageCopy::STATUS_SAVING,
                                 claimed_by: "prepare-other", claimed_at: 1.minute.ago)
        @boat.start(name: "halon-box-1", owner: OWNER)
        assert_equal SandboxImageCopy::STATUS_READY, SandboxImageCopy.find_by!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER)).status

        no_copy!
        @api.expects(:save_snapshot).with("bx_23456789", copy_for(OWNER)).returns({ "status" => "saving" })
        @boat.prepare_image!(OWNER.workspace_id)
      end

      test "a box started while its workspace's copy is being saved pulls the image" do
        @api.stubs(:snapshot).returns({ "name" => copy_for(OWNER), "status" => "saving" })
        created = nil
        @api.expects(:create).with { |body, **| created = body }.returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:save_snapshot).never

        @boat.start(name: "halon-box-1", owner: OWNER)

        assert_nil created[:from]
      end

      test "a failed image copy is deleted so the next prepare can save it again under its name" do
        @api.stubs(:snapshot).returns({ "name" => copy_for(OWNER), "status" => "failed" })
        @api.stubs(:create).returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.stubs(:stop)
        saving = sequence("saving")
        @api.expects(:delete_snapshot).with(copy_for(OWNER)).in_sequence(saving)
        @api.expects(:save_snapshot).with("bx_23456789", copy_for(OWNER)).in_sequence(saving)

        @boat.prepare_image!(OWNER.workspace_id)
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
          { "name" => "halon-image-0000000000000000-aaaaaaaaaaaa", "status" => "ready", "createdAt" => 1.hour.ago.iso8601 },
          { "name" => image_copy_name, "status" => "ready", "createdAt" => 1.hour.ago.iso8601 },
          { "name" => copy_for(OWNER), "status" => "ready", "createdAt" => 1.hour.ago.iso8601 },
          { "name" => "web-stack", "status" => "ready", "createdAt" => 9.days.ago.iso8601 }
        ])
        @api.expects(:delete).with("bx_old").once
        @api.expects(:delete_snapshot).with("halon-kept-lost").once
        @api.expects(:delete_snapshot).with("halon-image-0000000000000000-aaaaaaaaaaaa").once
        @api.expects(:delete_snapshot).with(image_copy_name).once

        SandboxImageCopy.create!(provider: Integrations::Sandboxes::Boat::KEY, name: "halon-image-0000000000000000-aaaaaaaaaaaa", status: SandboxImageCopy::STATUS_READY)
        SandboxImageCopy.create!(provider: Integrations::Sandboxes::Boat::KEY, name: copy_for(OWNER), status: SandboxImageCopy::STATUS_READY)

        @boat.tidy(kept_refs: Set["halon-kept-known"])

        assert_equal [ copy_for(OWNER) ], SandboxImageCopy.where(provider: Integrations::Sandboxes::Boat::KEY).pluck(:name),
                     "only claims on this image's copies are kept, and the copy every workspace shared before is deleted"
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

      test "a run's box never saves the image copy, and a box starts only from its own workspace's copy" do
        first = Owner.new(workspace_id: "0b6f6c1e-58d4-4a8e-9a43-1f1f2b0c9d11", key: "investigation-1")
        second = Owner.new(workspace_id: "7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f", key: "investigation-2")
        @api.stubs(:snapshot).with(copy_for(first)).returns({ "name" => copy_for(first), "status" => "ready" })
        @api.stubs(:snapshot).with(copy_for(second)).raises(BoatApi::NotFound, "boat.dev answered 404: Named snapshot not found. (not_found)")
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "idle" })
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 0 })
        froms = []
        @api.stubs(:create).with { |body, **| froms << body[:from] }.returns({ "sandbox" => { "id" => "bx_23456789" } })
        @api.expects(:save_snapshot).never

        @boat.start(name: "halon-box-1", owner: first)
        @boat.start(name: "halon-box-2", owner: second)
        @boat.start(name: "halon-box-3")

        assert_equal [ copy_for(first), nil, nil ], froms, "the second workspace pulls the image rather than start from the first's disk"
        assert_not_equal copy_for(first), copy_for(second)
      end

      test "a workspace's copy is saved only ahead of need, from a box no run used" do
        workspace_id = "7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f"
        no_copy!
        @api.expects(:create).once.returns({ "sandbox" => { "id" => "bx_prepare" } })
        @api.expects(:save_snapshot).once.with("bx_prepare", copy_for(Owner.new(workspace_id: workspace_id, key: "x"))).returns({ "status" => "saving" })
        @api.expects(:stop).once.with("bx_prepare")

        @boat.prepare_image!(workspace_id)
      end

      private

      def copy_for(owner) = "halon-image-#{Digest::SHA256.hexdigest(Sandboxes.image)[0, 16]}-#{Digest::SHA256.hexdigest(owner.workspace_id)[0, 12]}"

      def image_copy_name ="halon-image-#{Digest::SHA256.hexdigest(Sandboxes.image)[0, 16]}"

      def no_copy!
        @api.stubs(:snapshot).raises(BoatApi::NotFound, "boat.dev answered 404: Named snapshot not found. (not_found)")
        @api.stubs(:sandbox).returns({ "id" => "bx_23456789", "state" => "idle" })
        @api.stubs(:command_status).returns({ "status" => "exited", "exitCode" => 0 })
      end
    end
  end
end
