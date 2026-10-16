require "ipaddr"

# Which addresses are inside a network rather than on the public internet. Every check that keeps a call made from
# Firefight's network from reaching inside it asks this one rule.
module NetworkAddress
  # Reserved ranges IPAddr does not call private, such as the shared range clouds use inside their own networks.
  RESERVED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ff00::/8].map { |range| IPAddr.new(range) }.freeze

  # IPv6 ranges that carry an IPv4 address, with where its 32 bits sit: NAT64 and the old compatible form at the end,
  # 6to4 right after its prefix. A host that resolves to one reaches that IPv4 address wherever the network translates it.
  CARRIES_IPV4 = { IPAddr.new("64:ff9b::/96") => 0, IPAddr.new("::/96") => 0, IPAddr.new("2002::/16") => 80 }.freeze

  def self.private_ip?(ip)
    ip.private? || ip.loopback? || ip.link_local? || ip.to_s == "::" ||
      RESERVED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) } ||
      (ip.ipv4_mapped? && private_ip?(ip.native)) ||
      carried_ipv4(ip)&.then { |carried| private_ip?(carried) } || false
  end

  def self.carried_ipv4(ip)
    return unless ip.ipv6?

    shift = CARRIES_IPV4.find { |range, _| range.include?(ip) }&.last
    shift && IPAddr.new((ip.to_i >> shift) & 0xffff_ffff, Socket::AF_INET)
  end
  private_class_method :carried_ipv4
end
