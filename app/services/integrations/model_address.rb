module Integrations
  # The shared contract for checking an address a workspace's AI account named, for callers outside the integrations
  # layer that make the call themselves, such as the code fix proxy. Answers the address to connect to, or raises
  # PublicAddress::Refused with why it may not be reached.
  module ModelAddress
    Refused = PublicAddress::Refused
    # An operator may still allow named private hosts in INTEGRATION_AI_ACCOUNT_PRIVATE_HOSTS, as for any connection.
    PROVIDER_KEY = :ai_account

    def self.ip_for!(host) = PublicAddress.check!(host, provider_key: PROVIDER_KEY).ip.to_s
  end
end
