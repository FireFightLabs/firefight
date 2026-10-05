module Integrations
  module HealthProbes
    # Lists SigNoz's services through signoz_list_services, which only works with a key SigNoz accepts, and keeps the
    # address of the team's SigNoz from the page each service links to, so a count of a service's spans links to its
    # page. The tool, its answer (data, each with a webUrl) and the page address (<base>/services/<name>) are from
    # SigNoz/signoz-mcp-server (internal/handler/tools/services.go, pkg/paginate, pkg/util/weburl.go).
    class Signoz < RemoteReader
      LIST_SERVICES = "signoz_list_services".freeze
      SERVICE_PAGE = %r{\A(?<base>https?://[^/?#@]+(?:/[^?#@]*)?)/services/[^/?#]+\z}

      def self.address(settings) = settings&.learned.to_h["address"].presence

      def check!
        result = call(LIST_SERVICES, { "limit" => 1 })
        return if result.nil?
        refused!(LIST_SERVICES, result)

        body = Capabilities::Answers.data(result)
        page = body.is_a?(Hash) ? Array(body["data"]).filter_map { |service| service["webUrl"] if service.is_a?(Hash) }.first : nil
        base = page.to_s.match(SERVICE_PAGE)&.[](:base)
        { "address" => base } if base
      end
    end
  end
end
