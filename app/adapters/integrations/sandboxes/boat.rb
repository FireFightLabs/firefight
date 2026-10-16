module Integrations
  module Sandboxes
    # Boxes as boat.dev sandboxes, Linux VMs in the EU with Docker (docs.boat.dev/machines). The sandbox image runs in
    # one as a container, reached at the https address boat gives its port (docs.boat.dev/hosting). Named snapshots
    # keep the pulled image and each workspace's prepared repositories, so a later box starts from them in seconds.
    class Boat < Provider
      PORT = 8080
      CONTAINER = "firefight-sandbox".freeze
      DEFAULT_SIZE = "default".freeze
      REGION = "the EU".freeze
      # Dollars by the hour for each size (docs.boat.dev/pricing), billed by the second while a sandbox runs.
      HOURLY_MICROS = { "small" => 18_000, "default" => 36_000, "large" => 72_000, "xlarge" => 200_000 }.freeze
      # A sandbox archives itself this long after it starts, so one the app lost track of never runs on.
      TTL = 6.hours
      READY_STATES = %w[ready idle running].freeze
      FAILED_STATES = %w[error cancelled].freeze
      GONE_STATES = %w[archiving archived cancelled].freeze
      # Pulling the image into a sandbox that has no copy of it yet can take minutes.
      START_TIMEOUT = 15.minutes
      POLL_EVERY = 2
      # A stopped box is archived first, so a copy being saved from it is never cut short, and deleted after this.
      DELETE_AFTER = 1.hour
      # A copy of the image is made again after this, so an image whose tag moves (edge) is not run stale for long.
      IMAGE_KEPT_FOR = 1.day
      # A prepared copy's named snapshot is written before its row, so a snapshot no row names is left this long first.
      KEPT_GRACE = 1.hour
      IMAGE_PREFIX = "halon-image-".freeze
      KEPT_PREFIX = "halon-kept-".freeze
      PHASES = {
        "init" => ProviderSandbox::PHASE_STARTING, "provisioning" => ProviderSandbox::PHASE_STARTING, "provisioned" => ProviderSandbox::PHASE_STARTING,
        "cloning" => ProviderSandbox::PHASE_STARTING, "ready" => ProviderSandbox::PHASE_RUNNING, "idle" => ProviderSandbox::PHASE_RUNNING,
        "running" => ProviderSandbox::PHASE_RUNNING, "archiving" => ProviderSandbox::PHASE_STOPPING, "archived" => ProviderSandbox::PHASE_STOPPED,
        "error" => ProviderSandbox::PHASE_FAILED, "cancelled" => ProviderSandbox::PHASE_FAILED
      }.freeze
      SAVING = "saving".freeze
      READY = "ready".freeze
      FAILED = "failed".freeze
      SNAPSHOT_PHASES = { SAVING => ProviderSandbox::PHASE_STARTING, READY => ProviderSandbox::PHASE_READY, FAILED => ProviderSandbox::PHASE_FAILED }.freeze
      FREE_SNAPSHOTS = 10
      # $1.70 a month for each named snapshot beyond the free ones.
      SNAPSHOT_MONTHLY_MICROS = 1_700_000
      # boat's snapshots carry Docker named volumes and not a container's own layer (docs.boat.dev/snapshots), so
      # everything a prepared copy needs lives on one.
      VOLUMES = {
        "halon-code" => "/code", "halon-work" => "/work", "halon-runs" => "/runs", "halon-mise" => "/opt/mise",
        "halon-runner" => "/home/runner", "halon-postgres" => "/var/lib/postgresql"
      }.freeze
      # While a sandbox is still mounting its disk after a fork, a command answers that it did not run.
      NOT_YET = /sandbox_restoring|sandbox_starting/
      # boat cuts a sandbox's name at this length, and its name is the only place a sandbox carries who it is for.
      NAME_LIMIT = 120
      TOKEN_PARAMETER = "_token".freeze
      TOKEN_COOKIE = "_port_auth".freeze

      def initialize(api: BoatApi.new)
        @api = api
      end

      def relayed? = true

      # boat's address carries the port's access token as _token, which boat answers with a redirect that sets the
      # _port_auth cookie, so a client that follows no redirects sends the token as that cookie (docs.boat.dev/hosting).
      def box(ref:, address:, key:) = Box.new(ref: ref, address: address, key: key, relayed: true, cookies: { TOKEN_PARAMETER => TOKEN_COOKIE })

      def size = ENV["BOAT_SANDBOX_TYPE"].presence || DEFAULT_SIZE

      def hourly_micros = HOURLY_MICROS[size]

      def keeps_copies? = true

      # boat runs every sandbox in the EU and offers no choice of place (docs.boat.dev/machines).
      def region = REGION

      # A box from from, a prepared copy's named snapshot, or from its workspace's copy of the image when one is ready,
      # so the image is pulled only until that copy exists. A run's box never saves a copy, since boat captures a running
      # box over minutes and a capture asked for as it starts can hold the repository the run pushes into it. The pull is
      # followed here, within START_TIMEOUT, so the box handed back is already running the image and the client's wait
      # for its health check is only for it to answer.
      def start(name:, owner: nil, from: nil, fail_fast: false)
        copy = (image_copy_name(owner.workspace_id) if owner && from.nil?)
        ready = copy.present? && image_copy_status(copy) == READY
        SandboxImageCopy.ready!(SandboxProviders::BOAT, copy) if ready
        _ref, box = bring_up(owned_name(name, owner), from: from || (copy if ready), fail_fast: fail_fast)
        box
      end

      # Starts a box only to save a workspace's image copy, a box no run ever used, when boat has none ready or saving
      # and this call wins the claim, and archives it once the save is asked for, which boat lets finish. Each workspace
      # has its own copy, so no box ever starts from another workspace's disk.
      def prepare_image!(workspace_id)
        copy = image_copy_name(workspace_id)
        status = image_copy_status(copy)
        return if [ READY, SAVING ].include?(status)

        claimant = "prepare-#{SecureRandom.hex(8)}"
        return unless claimed?(copy, claimant)

        begin
          ref, _box = bring_up(Sandboxes.box_name, from: nil, fail_fast: false)
        rescue Sandboxes::Error => error
          return let_go(copy, claimant, error)
        end
        save_image_copy(ref, copy, claimant, replacing: status == FAILED)
        stop(ref)
      end

      # boat keeps no variable the app could read the box's key back from, so the container is started again with a new
      # one, keeping everything on the box's volumes.
      def reclaim(ref) = run_image(ref)

      # Archived, so it costs nothing from now on. tidy deletes it for good once nothing can be saving a copy from it.
      def stop(ref)
        @api.stop(ref)
      rescue BoatApi::NotFound
        nil
      end

      def running
        @api.sandboxes.filter_map do |sandbox|
          next unless sandbox["name"].to_s.start_with?(NAME_PREFIX) && !GONE_STATES.include?(sandbox["state"])

          Running.new(ref: sandbox["id"], started_at: (Time.zone.parse(sandbox["createdAt"].to_s) if sandbox["createdAt"]))
        end
      end

      # Every sandbox and named snapshot named like Firefight's, in any state. boat keeps an account's 10 newest named
      # snapshots free and charges for each one beyond (docs.boat.dev/snapshots, Named snapshot pricing), so an older
      # one of Firefight's past the tenth carries that price.
      def inventory
        boxes = @api.sandboxes.select { |sandbox| sandbox["name"].to_s.start_with?(NAME_PREFIX) }.map do |sandbox|
          Held.new(kind: ProviderSandbox::KIND_BOX, ref: sandbox["id"], name: sandbox["name"], state: sandbox["state"], phase: PHASES[sandbox["state"]],
                   size: sandbox["type"], started_at: stamp(sandbox["createdAt"]), updated_at: stamp(sandbox["updatedAt"]), owner: Owner.in(sandbox["name"]))
        end
        newest_first = @api.snapshots.sort_by { |snapshot| stamp(snapshot["createdAt"]) || Time.zone.at(0) }.reverse
        copies = newest_first.each_with_index.filter_map do |snapshot, index|
          next unless snapshot["name"].to_s.start_with?(KEPT_PREFIX, IMAGE_PREFIX)

          purpose = snapshot["name"].to_s.start_with?(KEPT_PREFIX) ? ProviderSandbox::PURPOSE_PREPARED : ProviderSandbox::PURPOSE_IMAGE
          Held.new(kind: ProviderSandbox::KIND_SNAPSHOT, ref: snapshot["name"], purpose: purpose, name: snapshot["name"], state: snapshot["status"],
                   phase: SNAPSHOT_PHASES[snapshot["status"]], size: snapshot["type"],
                   started_at: stamp(snapshot["createdAt"]), byte_size: snapshot["sizeBytes"],
                   monthly_micros: index >= FREE_SNAPSHOTS ? SNAPSHOT_MONTHLY_MICROS : 0)
        end
        boxes + copies
      end

      # Deleted for good, its snapshots with it.
      def delete(ref)
        @api.delete(ref)
      rescue BoatApi::NotFound
        nil
      end

      # Starts keeping the box's disk as it is now under a new name, answering the name. boat takes a fresh capture of a
      # running sandbox first (docs.boat.dev/api/reference/snapshots/save-named-snapshot), which can take minutes.
      def keep(ref)
        name = "#{KEPT_PREFIX}#{SecureRandom.hex(10)}"
        @api.save_snapshot(ref, name)
        name
      end

      def kept_ready?(name) = @api.snapshot(name)["status"] == READY

      def discard(name)
        @api.delete_snapshot(name)
      rescue BoatApi::NotFound
        nil
      end

      # Deletes boxes archived for DELETE_AFTER, prepared copies no row names, and copies of an image that is no longer
      # run or was made more than IMAGE_KEPT_FOR ago, with the claims on saving the ones no longer run.
      def tidy(kept_refs:)
        SandboxImageCopy.forget_others!(SandboxProviders::BOAT, image_copies_prefix)
        @api.sandboxes.each do |sandbox|
          next unless sandbox["name"].to_s.start_with?(NAME_PREFIX) && sandbox["state"] == "archived"
          next unless older_than?(sandbox["updatedAt"], DELETE_AFTER)

          forget(sandbox["id"])
        end
        @api.snapshots.each do |snapshot|
          name = snapshot["name"].to_s
          stale = (name.start_with?(KEPT_PREFIX) && !kept_refs.include?(name) && older_than?(snapshot["createdAt"], KEPT_GRACE)) ||
                  (name.start_with?(IMAGE_PREFIX) && (!name.start_with?(image_copies_prefix) || older_than?(snapshot["createdAt"], IMAGE_KEPT_FOR)))
          discard(name) if stale
        end
      end

      def hourly_micros_for(size) = HOURLY_MICROS[size]

      private

      # The box's name with who it is for, unless that would not fit, when the box goes without.
      def owned_name(name, owner)
        owned = owner && "#{NAME_PREFIX}#{owner.text}"
        owned && owned.length <= NAME_LIMIT ? owned : name
      end

      # Starts the sandbox image in the box with a key of its own, answering how to reach it.
      def run_image(ref)
        key = SecureRandom.hex(32)
        run!(ref, start_script(key))
        address = @api.host(ref, PORT, title: "Firefight sandbox")
        raise Error, "boat.dev gave no address for the sandbox's port." if address.blank?

        box(ref: ref, address: address, key: key)
      end

      # One named snapshot per image and workspace, named by digests of both, since a snapshot name takes only lower case
      # letters, digits and dashes.
      def image_copies_prefix = "#{IMAGE_PREFIX}#{Digest::SHA256.hexdigest(Sandboxes.image)[0, 16]}-"

      def image_copy_name(workspace_id) = "#{image_copies_prefix}#{Digest::SHA256.hexdigest(workspace_id.to_s)[0, 12]}"

      # The image copy's status in boat's words, saving, ready or failed, or nil when there is none.
      def image_copy_status(copy)
        @api.snapshot(copy)["status"]
      rescue BoatApi::NotFound
        nil
      end

      # Creates a box, names it, waits for boat to have it ready and runs the image in it, answering its ref and how to
      # reach it. A box that does not get that far is deleted.
      def bring_up(name, from:, fail_fast:)
        created = @api.create({ type: size, ttlSeconds: TTL.to_i, noEnv: true, failFast: fail_fast, from: from }.compact, idempotency_key: SecureRandom.uuid)
        ref = created.dig("sandbox", "id") || created["id"]
        raise Error, "boat.dev created no sandbox." if ref.blank?

        @api.rename(ref, name)
        wait_until_up(ref)
        [ ref, run_image(ref) ]
      rescue StandardError
        forget(ref) if ref.present?
        raise
      end

      # Whether claimant won the save of the image copy. The copy is only a head start for the next box, so a claim
      # that cannot be read is simply not won.
      def claimed?(copy, claimant)
        SandboxImageCopy.claim!(SandboxProviders::BOAT, copy, claimant)
      rescue ActiveRecord::ActiveRecordError => error
        let_go(copy, nil, error)
        false
      end

      # Saved only by the claim's winner from a box that is up. A box stays up when the copy cannot be saved, and the
      # claim is let go of for a later box. A failed copy is deleted first, since it holds the name.
      def save_image_copy(ref, copy, claimant, replacing:)
        discard(copy) if replacing
        @api.save_snapshot(ref, copy)
      rescue BoatApi::Error => error
        let_go(copy, claimant, error)
      end

      # A claim that cannot be let go of here runs out after SandboxImageCopy::ABANDONED_AFTER.
      def let_go(copy, claimant, error)
        Rails.logger.warn({ event: "code_box.image_copy_failed", provider: SandboxProviders::BOAT, claimant: claimant, error: error.message }.to_json)
        SandboxImageCopy.failed!(SandboxProviders::BOAT, copy, claimant) if claimant
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def wait_until_up(ref)
        deadline = clock + START_TIMEOUT
        loop do
          sandbox = @api.sandbox(ref)
          return if READY_STATES.include?(sandbox["state"])
          raise Error, Sentence.join("boat.dev could not start the sandbox", sandbox["error"].presence || sandbox["state"]) if FAILED_STATES.include?(sandbox["state"])
          raise Error, "boat.dev did not have the sandbox ready within #{START_TIMEOUT.inspect}." if clock > deadline

          pause(POLL_EVERY)
        end
      end

      # Runs the script in the background and follows it to the end, since pulling the image can outlast one request.
      def run!(ref, script)
        process = start_command(ref, script)
        deadline = clock + START_TIMEOUT
        loop do
          status = @api.command_status(ref, process)
          if status["status"] != "running"
            return if status["exitCode"].to_i.zero? && status["status"] == "exited"

            raise Error, Sentence.join("The sandbox image did not start on boat.dev", status["stderr"].to_s.strip.lines.last.presence || status["status"])
          end
          raise Error, "The sandbox image did not start on boat.dev within #{START_TIMEOUT.inspect}." if clock > deadline

          pause(POLL_EVERY)
        end
      end

      def start_command(ref, script, tries: 3)
        @api.run_detached(ref, script)
      rescue BoatApi::Error => error
        raise unless error.message.match?(NOT_YET) && (tries -= 1).positive?

        pause(POLL_EVERY)
        retry
      end

      # The container that was running when a copy was saved comes back with it, so it is replaced by one with this
      # box's own key. The VM's Docker socket lets the box start a setup's service images beside itself.
      def start_script(key)
        mounts = VOLUMES.map { |volume, path| "-v #{volume}:#{path}" }.join(" ")
        [
          "set -e",
          "sudo docker rm -f #{CONTAINER} >/dev/null 2>&1 || true",
          "sudo docker run -d --name #{CONTAINER} -p #{PORT}:#{PORT} -e SANDBOX_KEY=#{key} -v /var/run/docker.sock:/var/run/docker.sock " \
          "#{mounts} #{Shellwords.escape(Sandboxes.image)} >/dev/null"
        ].join("\n")
      end

      def forget(ref)
        @api.delete(ref)
      rescue BoatApi::Error => error
        Rails.logger.warn({ event: "code_box.delete_failed", provider: SandboxProviders::BOAT, box_ref: ref, error: error.message }.to_json)
      end

      def stamp(value) = value.present? ? Time.zone.parse(value.to_s) : nil

      def older_than?(stamp, age) = stamp.present? && Time.zone.parse(stamp.to_s) < age.ago

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # A stop (StopSignal) ends the wait, and start lets go of the box it was starting.
      def pause(seconds) = StopSignal.pause(seconds)
    end
  end
end
