require "ipaddr"

# Which addresses are inside a network rather than on the public internet. Every check that keeps a call made from
# Firefight's network from reaching inside it asks this one rule.
module NetworkAddress
  # Reserved ranges IPAddr does not call private, such as the shared range clouds use inside their own networks.
  RESERVED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ff00::/8].map { |range| IPAddr.new(range) }.freeze

  def self.private_ip?(ip)
    ip.private? || ip.loopback? || ip.link_local? || ip.to_s == "::" ||
      RESERVED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) } ||
      (ip.ipv4_mapped? && private_ip?(ip.native))
  end
end
