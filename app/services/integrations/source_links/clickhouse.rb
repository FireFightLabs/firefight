module Integrations
  module SourceLinks
    # Links a ClickHouse Cloud result to its console page where ClickHouse documents one. Its personal data access
    # reference gives an organization's billing page, organizations/<id>/billing on the console, and the docs give no
    # address for a service, its backups or its ClickPipes. So only an organization's cost links. The console is the
    # registry's site.
    class Clickhouse
      NAME = "the ClickHouse Cloud console".freeze
      COST = "get_organization_cost".freeze
      ORGANIZATION = "organizationId".freeze
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      def initialize(settings)
        @site = settings&.site.to_s.delete_suffix("/")
      end

      def link(tool_name:, arguments:, text: "")
        organization = arguments.to_h.stringify_keys[ORGANIZATION].to_s
        return unless tool_name == COST && organization.match?(UUID) && @site.present?

        Telemetry::Link.new(provider: NAME, url: "#{@site}/organizations/#{organization}/billing")
      end
    end
  end
end
