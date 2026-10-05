module Integrations
  module MapReaders
    # Puts ClickHouse Cloud on the resource map. Every organization the connection reaches and its services are read
    # through get_organizations and get_services_list, the tools ClickHouse documents for its remote MCP server. A
    # service is a database on the map, its account is the organization's id, and its details are the Service fields
    # ClickHouse's Cloud API documents.
    class Clickhouse < RemoteReader
      PROVIDER = Capabilities::Clickhouse::PROVIDER_KEY
      NAME = Capabilities::Clickhouse::PROVIDER
      LIST_ORGANIZATIONS = "get_organizations".freeze
      LIST_SERVICES = "get_services_list".freeze
      KINDS = [ ResourceMap::KIND_DATABASE ].freeze

      def initialize(...)
        super
        @resources = []
      end

      def map
        organizations = read(LIST_ORGANIZATIONS, "organizations", {})
        organizations&.each do |organization|
          services = read(LIST_SERVICES, "services in #{organization['name'] || organization['id']}",
                          { Capabilities::Clickhouse::ORGANIZATION => organization["id"] })
          services&.each { |service| service(organization, service) }
        end
        ResourceMap::Snapshot.new(resources: @resources, gaps: gaps)
      end

      private

      def service(organization, service)
        return if service["id"].blank?

        @resources << ResourceMap::Found.new(
          provider: PROVIDER, account: organization["id"].to_s, kind: ResourceMap::KIND_DATABASE, external_id: service["id"].to_s,
          name: service["name"].presence || service["id"].to_s, status: service["state"],
          details: {
            "organization" => organization["name"], "cloud" => service["provider"], "region" => service["region"],
            "version" => service["clickhouseVersion"], "replicas" => service["numReplicas"], "idle_scaling" => service["idleScaling"],
            "read_only" => service["isReadonly"]
          }.compact
        )
      end

      # The list a tool answered, from the Cloud API's result envelope or as a bare list, or nil with a gap.
      def read(tool, what, arguments)
        data = listing(tool, what, arguments, kinds: KINDS)
        data = data["result"] if data.is_a?(Hash) && data.key?("result")
        return data if data.is_a?(Array) && data.all?(Hash)

        gap("ClickHouse answered the #{what} in a shape Firefight does not read.", kinds: KINDS) unless data.nil?
      end
    end
  end
end
