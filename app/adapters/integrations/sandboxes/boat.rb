module Integrations
  module Sandboxes
    # Boxes as boat.dev sandboxes, Linux VMs in the EU with Docker (docs.boat.dev/machines). The sandbox image runs in
    # one as a container, reached at the https address boat gives its port (docs.boat.dev/hosting). Named snapshots
    # keep the pulled image and each workspace's prepared repositories, so a later box starts from them in seconds.
    class Boat < Provider
      PORT = 8080
      CONTAINER = "firefight-sandbox".freeze
      DEFAULT_SIZE = "default".freeze
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
      # boat's snapshots carry Docker named volumes and not a container's own layer (docs.boat.dev/snapshots), so
      # everything a prepared copy needs lives on one.
      VOLUMES = {
        "halon-code" => "/code", "halon-work" => "/work", "halon-runs" => "/runs", "halon-mise" => "/opt/mise",
        "halon-runner" => "/home/runner", "halon-postgres" => "/var/lib/postgresql"
      }.freeze
      # While a sandbox is still mounting its disk after a fork, a command answers that it did not run.
      NOT_YET = /sandbox_restoring|sandbox_starting/

      def initialize(api: BoatApi.new)
        @api = api
      end

      def relayed? = true

      def size = ENV["BOAT_SANDBOX_TYPE"].presence || DEFAULT_SIZE

      def hourly_micros = HOURLY_MICROS[size]

      def keeps_copies? = true

      # A box from from, a prepared copy's named snapshot, or from the image's own copy when there is one ready, so the
      # image is pulled only by the first box of each version.
      def start(name:, from: nil, fail_fast: false)
        image_copy = from ? nil : ready_image_copy
        created = @api.create({ type: size, ttlSeconds: TTL.to_i, noEnv: true, failFast: fail_fast, from: from || image_copy }.compact,
                              idempotency_key: SecureRandom.uuid)
        ref = created.dig("sandbox", "id") || created["id"]
        raise Error, "boat.dev created no sandbox." if ref.blank?

        begin
          @api.rename(ref, name)
          wait_until_up(ref)
          key = SecureRandom.hex(32)
          run!(ref, start_script(key))
          address = @api.host(ref, PORT, title: "Firefight sandbox")
          raise Error, "boat.dev gave no address for the sandbox's port." if address.blank?

          @api.save_snapshot(ref, image_copy_name) unless from || image_copy
          Box.new(ref: ref, address: address, key: key, relayed: true)
        rescue StandardError
          forget(ref)
          raise
        end
      end

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

      # Starts keeping the box's disk as it is now under a new name, answering the name. boat takes a fresh capture of a
      # running sandbox first (docs.boat.dev/api/reference/snapshots/save-named-snapshot), which can take minutes.
      def keep(ref)
        name = "#{KEPT_PREFIX}#{SecureRandom.hex(10)}"
        @api.save_snapshot(ref, name)
        name
      end

      def kept_ready?(name) = @api.snapshot(name)["status"] == "ready"

      def discard(name)
        @api.delete_snapshot(name)
      rescue BoatApi::NotFound
        nil
      end

      # Deletes boxes archived for DELETE_AFTER, prepared copies no row names, and copies of an image that is no longer
      # run or was made more than IMAGE_KEPT_FOR ago.
      def tidy(kept_refs:)
        @api.sandboxes.each do |sandbox|
          next unless sandbox["name"].to_s.start_with?(NAME_PREFIX) && sandbox["state"] == "archived"
          next unless older_than?(sandbox["updatedAt"], DELETE_AFTER)

          forget(sandbox["id"])
        end
        @api.snapshots.each do |snapshot|
          name = snapshot["name"].to_s
          stale = (name.start_with?(KEPT_PREFIX) && !kept_refs.include?(name) && older_than?(snapshot["createdAt"], KEPT_GRACE)) ||
                  (name.start_with?(IMAGE_PREFIX) && (name != image_copy_name || older_than?(snapshot["createdAt"], IMAGE_KEPT_FOR)))
          discard(name) if stale
        end
      end

      private

      # One named snapshot per image, named by a digest of it, since a snapshot name takes only lower case letters,
      # digits and dashes.
      def image_copy_name = "#{IMAGE_PREFIX}#{Digest::SHA256.hexdigest(Sandboxes.image)[0, 16]}"

      def ready_image_copy
        image_copy_name if kept_ready?(image_copy_name)
      rescue BoatApi::NotFound
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

      def older_than?(stamp, age) = stamp.present? && Time.zone.parse(stamp.to_s) < age.ago

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def pause(seconds) = sleep(seconds)
    end
  end
end
