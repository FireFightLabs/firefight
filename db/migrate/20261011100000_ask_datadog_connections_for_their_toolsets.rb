# Datadog's server offers only its core toolset unless the address asks for more, and Firefight's errors capability and
# skills read error tracking too. Each Datadog connection made through its server keeps its own address, host and path
# included, and gains the toolsets every new one asks for. An address that already names toolsets is left as it is.
class AskDatadogConnectionsForTheirToolsets < ActiveRecord::Migration[8.1]
  PROVIDER = "datadog".freeze
  TOOLSETS = "toolsets".freeze
  ASKED = "core,error-tracking".freeze

  def up
    each_connection do |integration, uri, query|
      next if query.any? { |name, _value| name == TOOLSETS }

      store(integration, uri, query + [ [ TOOLSETS, ASKED ] ])
    end
  end

  def down
    each_connection do |integration, uri, query|
      next unless query.include?([ TOOLSETS, ASKED ])

      store(integration, uri, query - [ [ TOOLSETS, ASKED ] ])
    end
  end

  private

  def each_connection
    Integration.where(provider: PROVIDER, kind: Integration::KIND_MCP).find_each do |integration|
      address = integration.settings.to_h["server_url"].to_s
      next if address.blank?

      uri = URI.parse(address)
      yield integration, uri, URI.decode_www_form(uri.query.to_s)
    rescue URI::InvalidURIError, ArgumentError
      next
    end
  end

  def store(integration, uri, query)
    uri.query = query.empty? ? nil : URI.encode_www_form(query).gsub("%2C", ",")
    integration.update_columns(settings: integration.settings.merge("server_url" => uri.to_s))
  end
end
