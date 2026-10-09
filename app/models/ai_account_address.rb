require "ipaddr"

# Whether an AI account's custom API base may be called. A hosted build refuses one on a private or loopback network,
# since the call would be made from inside Firefight's own network. This reads the address as written. The address it
# resolves to is checked when the account is saved (WorkspaceAiAccountService).
module AiAccountAddress
  SCHEMES = %w[http https].freeze
  LOCAL_NAMES = /\A(localhost|.*\.localhost|.*\.local|.*\.internal)\z/i

  def self.refusal(address, private_allowed:)
    uri = URI.parse(address.to_s)
    return "The API base URL must start with http:// or https://" unless SCHEMES.include?(uri.scheme) && uri.host.present?
    return "The API base URL cannot carry a user name or password" if uri.userinfo.present?
    return nil if private_allowed

    "The API base URL is on a private network, which Firefight does not reach" if private_host?(uri.host)
  rescue URI::InvalidURIError
    "The API base URL is not a valid address"
  end

  def self.private_host?(host)
    name = host.to_s.delete_prefix("[").delete_suffix("]")
    return true if name.match?(LOCAL_NAMES)

    NetworkAddress.private_ip?(IPAddr.new(name))
  rescue IPAddr::InvalidAddressError
    false
  end
end
