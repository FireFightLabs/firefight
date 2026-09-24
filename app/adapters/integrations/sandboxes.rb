module Integrations
  # Where the boxes Halon reads code in run. A provider only starts a box from the sandbox image, says where to reach
  # it and stops it. What runs inside is the same everywhere, so moving to another provider replaces one class.
  module Sandboxes
    class Error < Integrations::Error; end

    Box = Data.define(:ref, :address, :key)
    Running = Data.define(:ref, :started_at)

    PROVIDER_DOCKER = "docker".freeze
    PROVIDER_NORTHFLANK = "northflank".freeze
    PROVIDERS = [ PROVIDER_DOCKER, PROVIDER_NORTHFLANK ].freeze
    # Every box's name starts with this, so a provider lists only the boxes it started for Firefight.
    NAME_PREFIX = "halon-box-".freeze
    DEFAULT_IMAGE = "ghcr.io/firefightlabs/firefight-sandbox:latest".freeze

    def self.provider_key = ENV["SANDBOX_PROVIDER"].presence

    # nil when this install has not chosen one, and code reading says so rather than failing.
    def self.provider
      case provider_key
      when PROVIDER_DOCKER then Docker.new
      when PROVIDER_NORTHFLANK then Northflank.new
      when nil then nil
      else raise Error, "SANDBOX_PROVIDER is #{provider_key}, which is not one of #{PROVIDERS.join(', ')}."
      end
    end

    def self.image = ENV["SANDBOX_IMAGE"].presence || DEFAULT_IMAGE

    def self.box_name = "#{NAME_PREFIX}#{SecureRandom.hex(6)}"
  end
end
