module Integrations
  module SourceLinks
    # A call about one OpenStatus monitor links to that monitor's page on the provider's site (settings.site), at the
    # address OpenStatus's own notifications link to (openstatusHQ/openstatus, packages/notifications/base/src/utils/
    # message.ts, dashboardUrl). A call naming no monitor gets no link.
    class Openstatus
      NAME = "OpenStatus".freeze

      def initialize(settings)
        @site = settings&.site
      end

      def link(tool_name:, arguments:, text: "")
        id = arguments.to_h.stringify_keys[Capabilities::Openstatus::MONITOR_ID].to_s
        return unless @site && id.match?(/\A\d+\z/)

        Telemetry::Link.new(provider: NAME, url: "#{@site.chomp('/')}/monitors/#{id}")
      end
    end
  end
end
