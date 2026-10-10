module Integrations
  module ReadGuards
    # api_read only ever sends a GET to Azure Resource Manager, in a subscription the connection reads or for a resource
    # provider's own description, so what the guard settles is which answers hold secrets. Resource Manager hands a
    # secret's value only to a POST action (listKeys, listSecrets, config/appsettings/list, publishingcredentials/list,
    # Azure REST API reference), so no GET is refused for it. A few GETs still answer a key beside what they describe, such
    # as an Application Insights component's instrumentation key and connection string, a Web App's hybrid connection's
    # send key, or a storage link's SAS, so those fields are read as names (hidden), and a link signed with a SAS is hidden
    # wherever it sits.
    module Azure
      extend PathReads

      API_VERSION = "api-version".freeze
      SUBSCRIPTION = %r{\A/subscriptions/([^/]+)}
      # Inside a subscription, or a resource provider's own description and its operations.
      PATHS = %r{\A/subscriptions/[^/]+(/|\z)|\A/providers/[A-Za-z0-9.]+(/operations)?\z}
      REFUSED = {}.freeze
      SECRET_PATHS = /(?!)/
      SECRET_FIELDS = /key\z|keyvalue\z|keys\z|\Asas|sas(url|token|uri)\z|connection.?string|password|secret/i
      # What describes a key rather than holding it stays readable.
      DESCRIBING = /\A(name|type|id|keyname|sendkeyname|keyvaultreferenceidentity|keyvaulturi|keysource|keyvaultproperties)\z/i
      SAS = /[?&]sig=/

      def self.reading(tool_name, arguments)
        query = arguments["query"]
        unless query.is_a?(Hash) && query[API_VERSION].present?
          raise Refused, "query must carry #{API_VERSION}, the version of the resource type's API as its reference names it, such as {\"#{API_VERSION}\": \"2024-04-01\"}."
        end

        super
      end

      def self.reads?(tool_name, arguments) = arguments["query"].is_a?(Hash) && arguments["query"][API_VERSION].present? && super

      def self.refusal(path, query)
        return "A read stays inside this connection's subscription, so the path starts /subscriptions/<subscription id>/." unless path.match?(PATHS)

        super
      end

      def self.subscription_in(path) = path[SUBSCRIPTION, 1]

      def self.hidden(value)
        case value
        when Hash
          value.to_h do |key, inner|
            secret = key.to_s.match?(SECRET_FIELDS) && !key.to_s.match?(DESCRIBING)
            [ key, secret ? ApiReads.names_only(inner) : hidden(inner) ]
          end
        when Array then value.map { |inner| hidden(inner) }
        when String then value.match?(SAS) ? ApiReads::HIDDEN : value
        else value
        end
      end
    end
  end
end
