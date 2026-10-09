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

    def self.private?(ip) = NetworkAddress.private_ip?(ip)

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
