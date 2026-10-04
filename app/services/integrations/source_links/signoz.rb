module Integrations
  module SourceLinks
    # A count of a service's spans links to the service's page in SigNoz. Every team has its own address in a SigNoz
    # region, so the address is the one the health check read (HealthProbes::Signoz), not the region's. The page's
    # address is SigNoz's own (<base>/services/<name>, SigNoz/signoz-mcp-server pkg/util/weburl.go). Spans and traces carry their own page in SigNoz's answer, and a log
    # search gets no link, since SigNoz documents no address for its logs explorer that takes a query.
    class Signoz
      NAME = "SigNoz".freeze

      def initialize(settings)
        @address = HealthProbes::Signoz.address(settings)
      end

      def link(tool_name:, arguments:, text: "")
        address = @address
        service = arguments.to_h.stringify_keys["service"].to_s.strip
        return unless tool_name == Capabilities::Signoz::AGGREGATE && address && service.present?

        Telemetry::Link.new(provider: NAME, url: "#{address}/services/#{ERB::Util.url_encode(service)}")
      end
    end
  end
end
