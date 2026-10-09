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
    # start(name:, from:, fail_fast:) starts a box, from a copy the provider keeps when from names one, and fail_fast
    # asks a provider that can to refuse at once rather than wait for capacity, when there is another to try.
    class Provider
      def relayed? = false

      # The box's size in the provider's own words, such as a plan's name.
      def size = nil

      # What the provider charges for a box of this size by the hour, in millionths of a dollar, or nil when it puts no
      # price on it.
      def hourly_micros = nil

      def keeps_copies? = false

      # Tidies what the provider keeps beyond its running boxes. kept_refs are the copies the app still knows.
      def tidy(kept_refs:) = nil
    end
  end
end
