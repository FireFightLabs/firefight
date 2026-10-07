require "faraday/net_http"

module Integrations
  # The HTTP adapter for a model call to an address a workspace named itself, where private networks are refused. Every
  # request resolves the host again (ModelAddress) and connects to the address it checked, so a name that resolved to a
  # public address when the account was saved cannot be pointed inside Firefight's network later.
  class PublicAddressAdapter < Faraday::Adapter::NetHttp
    def net_http_connection(env)
      ip = ModelAddress.ip_for!(env[:url].hostname)
      super.tap { |http| http.ipaddr = ip unless env[:request][:proxy] }
    rescue ModelAddress::Refused => e
      raise Faraday::ConnectionFailed, e.message
    end
  end
end
