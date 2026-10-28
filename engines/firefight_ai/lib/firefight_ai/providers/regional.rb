module FirefightAi
  module Providers
    # A provider whose key works only in the region it was made in, each region at its own address. The region is a
    # setting, as Bedrock's is, and the address follows from it, so an account never names a host. A region can need
    # more than the key, such as a Model Studio workspace that is part of its address.
    class Regional < RubyLLM::Provider
      class << self
        # Each region's address, from the provider's own documentation.
        def addresses = raise(NotImplementedError)

        # The regions the provider serves, each with the settings it needs besides the key, such as a workspace ID.
        def regions = addresses.keys.index_with { [] }

        def address(config) = addresses[setting(config, :region)]

        def configured?(config)
          needs = regions[setting(config, :region)]
          return false unless needs && super

          needs.all? { |name| setting(config, name).present? }
        end

        def setting(config, name) = config.public_send(:"#{slug}_#{name}").to_s
      end

      def api_base = self.class.address(@config)

      def headers = { "Authorization" => "Bearer #{self.class.setting(@config, :api_key)}" }

      def account_identity = account_digest(api_base, self.class.setting(@config, :api_key))
    end
  end
end
