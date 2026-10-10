module Integrations
  # Where the boxes Halon reads code in run. A provider only starts a box from the sandbox image, says where to reach
  # it, what size it is and its price, and stops it. What runs inside is the same everywhere, so moving to another
  # provider replaces one class. Which provider a workspace's boxes go to is SandboxProviders' to say.
  module Sandboxes
    class Error < Integrations::Error; end

    # relayed is true when the address reaches the box through a proxy that may end a request that runs long, so the
    # client follows a long command in the background rather than holding one request open for it.
    Box = Data.define(:ref, :address, :key, :relayed) do
      def initialize(relayed: false, **) = super
    end
    Running = Data.define(:ref, :started_at)
    # Something a provider holds for Firefight, a box or a kept copy (ProviderSandbox::KINDS), in the provider's own
    # words for its state and size, with the state in ProviderSandbox::PHASES too. monthly_micros is what keeping a copy
    # costs a month, when it costs anything.
    # purpose is ProviderSandbox's, a run's box, the image's own copy or a prepared repository.
    # owner is who a box was started for, read back from what Firefight wrote on it, nil when it carries nothing.
    Held = Data.define(:kind, :ref, :purpose, :name, :state, :phase, :size, :started_at, :updated_at, :byte_size, :monthly_micros, :owner) do
      def initialize(purpose: ProviderSandbox::PURPOSE_RUN, name: nil, state: nil, phase: nil, size: nil, started_at: nil, updated_at: nil, byte_size: nil,
                     monthly_micros: nil, owner: nil, **) = super
    end

    # The workspace and the run's box key a box was started for, written on the box where its provider keeps such
    # things, so a box the app lost its row for can still be told apart and adopted. Neither is a secret.
    OWNER_PATTERN = /(?<workspace>\h{8}-\h{4}-\h{4}-\h{4}-\h{12})-(?<key>[a-z0-9][a-z0-9-]*)\z/
    Owner = Data.define(:workspace_id, :key) do
      # The owner at the end of text, written there by #text.
      def self.in(text)
        found = OWNER_PATTERN.match(text.to_s)
        found && new(workspace_id: found[:workspace], key: found[:key])
      end

      def text = "#{workspace_id}-#{key}"
    end

    # Every box's name starts with this, so a provider lists only the boxes it started for Firefight.
    NAME_PREFIX = "halon-box-".freeze
    IMAGE_REPOSITORY = "ghcr.io/firefightlabs/firefight-sandbox".freeze
    # Built from main whenever the box changes. An install that is not a release has no version tag to match.
    EDGE_TAG = "edge".freeze

    # The provider for key, nil for none.
    def self.provider(key)
      case key
      when SandboxProviders::DOCKER then Docker.new
      when SandboxProviders::NORTHFLANK then Northflank.new
      when SandboxProviders::BOAT then Boat.new
      when nil then nil
      else raise Error, "#{key} is not a sandbox provider. There are #{SandboxProviders::KEYS.join(', ')}."
      end
    end

    def self.image = ENV["SANDBOX_IMAGE"].presence || "#{IMAGE_REPOSITORY}:#{ENV['FIREFIGHT_RELEASE'].presence || EDGE_TAG}"

    def self.box_name = "#{NAME_PREFIX}#{SecureRandom.hex(6)}"

    # What every provider answers, and what a provider that does not keep a box's disk itself answers for the rest.
    # start(name:, owner:, from:, fail_fast:) starts a box for owner, from a copy the provider keeps when from names one,
    # and fail_fast asks a provider that can to refuse at once rather than wait for capacity, when there is another to try.
    # reclaim(ref) hands back a box the provider holds with a key the app knows, for a box adopted after its row was lost.
    class Provider
      def relayed? = false

      # The box's size in the provider's own words, such as a plan's name.
      def size = nil

      # What the provider charges for a box of this size by the hour, in millionths of a dollar, or nil when it puts no
      # price on it.
      def hourly_micros = nil

      # The price by the hour of a box of size, which may not be the size the provider starts now.
      def hourly_micros_for(size) = size == self.size ? hourly_micros : nil

      def keeps_copies? = false

      # Every box and kept copy the provider holds for Firefight, found by Firefight's name or label, running or not.
      def inventory
        running.map do |box|
          Held.new(kind: ProviderSandbox::KIND_BOX, ref: box.ref, name: box.ref, state: "running", phase: ProviderSandbox::PHASE_RUNNING, started_at: box.started_at)
        end
      end

      # Removes a box for good. Stopping one already removes it on a provider that keeps nothing.
      def delete(ref) = stop(ref)

      # Lets go of a kept copy. A provider that keeps none has none to let go of.
      def discard(_ref) = nil

      # Tidies what the provider keeps beyond its running boxes. kept_refs are the copies the app still knows.
      def tidy(kept_refs:) = nil
    end
  end
end
