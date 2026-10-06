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
      DETAILS = Capabilities::Clickhouse::DETAILS

      def initialize(...)
        super
        @resources = []
        @endpoints = []
        @undescribed = 0
      end

      def map
        organizations = read(LIST_ORGANIZATIONS, "organizations", {})
        organizations&.each do |organization|
          services = read(LIST_SERVICES, "services in #{organization['name'] || organization['id']}",
                          { Capabilities::Clickhouse::ORGANIZATION => organization["id"] })
          services&.each { |service| service(organization, service) }
        end
        if @undescribed.positive?
          gap("ClickHouse did not say where #{@undescribed} #{'service'.pluralize(@undescribed)} #{@undescribed == 1 ? 'is' : 'are'} reached" \
              "#{" and #{DETAILS} is switched off" unless on?(DETAILS)}, so settings that name #{@undescribed == 1 ? 'it' : 'them'} are not linked.",
              kinds: [], settings: true)
        end
        ResourceMap::Snapshot.new(resources: @resources, gaps: gaps, endpoints: @endpoints)
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
        addresses(organization, service, @resources.last)
      end

      # Where a service is reached, its Service object's endpoints, each a protocol, host and port, such as https on
      # 8443 and nativesecure on 9440 (https://clickhouse.com/docs/cloud/manage/api/swagger, Service). The list may
      # leave them out, so a service without them is described with get_service_details when that tool is on.
      def addresses(organization, service, found)
        return if workspace.nil?

        endpoints = service["endpoints"].presence || described(organization, service)
        return @undescribed += 1 unless endpoints.is_a?(Array)

        endpoints.select { |endpoint| endpoint.is_a?(Hash) }.each do |endpoint|
          @endpoints << ResourceMap::Endpoint.at(resource: found.key, host: endpoint["host"], port: endpoint["port"], workspace: workspace)
        end
      end

      def described(organization, service)
        return unless on?(DETAILS) && !@describing_refused

        answer = call(DETAILS, { Capabilities::Clickhouse::ORGANIZATION => organization["id"], Capabilities::Clickhouse::SERVICE => service["id"] },
                      "where #{service['name'] || service['id']} is reached")
        @describing_refused = answer.nil? || answer["isError"]
        data = @describing_refused ? nil : Capabilities::Answers.data(answer)
        data = data["result"] if data.is_a?(Hash) && data["result"].is_a?(Hash)
        data["endpoints"] if data.is_a?(Hash)
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
