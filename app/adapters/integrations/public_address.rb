require "ipaddr"
require "socket"

module Integrations
  # Whether a host a workspace names itself, such as its own database, cluster or code host, may be reached from
  # Firefight's network. A private, loopback, link-local or reserved address is refused unless an operator allowed it in
  # INTEGRATION_<PROVIDER>_PRIVATE_HOSTS (comma separated names, addresses or ranges), since a connection made from
  # Firefight's network would otherwise reach inside it. The caller connects to the address checked here, so the name
  # cannot point somewhere else between the check and the call.
  module PublicAddress
    class Refused < Integrations::Error; end

    # Reserved ranges IPAddr does not call private, such as the shared range clouds use inside their own networks.
    RESERVED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ff00::/8].map { |range| IPAddr.new(range) }.freeze

    # The address checked, and whether it is a private one an operator allowed.
    Checked = Data.define(:ip, :private)

    def self.allowed_env(provider_key) = "INTEGRATION_#{provider_key.to_s.upcase}_PRIVATE_HOSTS"

    # The host's address to connect to, or Refused saying why it may not be reached.
    def self.check!(host, provider_key:)
      ip = resolve(host)
      return Checked.new(ip: ip, private: false) unless private?(ip)
      return Checked.new(ip: ip, private: true) if allowed?(host, ip, ENV.fetch(allowed_env(provider_key), ""))

      raise Refused, "#{host} is on a private network, which Firefight does not connect to."
    end

    def self.resolve(host)
      IPAddr.new(Addrinfo.getaddrinfo(host, nil, nil, :STREAM).first.ip_address)
    rescue SocketError, IPAddr::InvalidAddressError
      raise Refused, "#{host} could not be found."
    end

    def self.private?(ip)
      ip.private? || ip.loopback? || ip.link_local? || ip.to_s == "::" ||
        RESERVED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) } ||
        (ip.ipv4_mapped? && private?(ip.native))
    end

    def self.allowed?(host, ip, allowed)
      allowed.to_s.split(",").map(&:strip).compact_blank.any? do |entry|
        entry.casecmp?(host) || IPAddr.new(entry).include?(ip)
      rescue IPAddr::InvalidAddressError
        false
      end
    end
    private_class_method :resolve, :private?, :allowed?
  end
end
