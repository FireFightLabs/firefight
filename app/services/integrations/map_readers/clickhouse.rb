module Integrations
  module MapReaders
    # Puts ClickHouse Cloud on the resource map. Every organization the connection reaches and its services are read
    # through get_organizations and get_services_list, the tools ClickHouse documents for its remote MCP server. A
    # service is a database on the map, its account is the organization's id, and its details are the Service fields
    # ClickHouse's Cloud API documents. Each service's ClickPipes, read with list_clickpipes, are pipelines part of it,
    # named service/pipe, with the ClickPipe object's state, source and destination
    # (https://clickhouse.com/docs/cloud/manage/api/swagger, ClickPipe).
    class Clickhouse < RemoteReader
      PROVIDER = Capabilities::Clickhouse::PROVIDER_KEY
      NAME = Capabilities::Clickhouse::PROVIDER
      LIST_ORGANIZATIONS = "get_organizations".freeze
      LIST_SERVICES = "get_services_list".freeze
      LIST_CLICKPIPES = Capabilities::Clickhouse::LIST_CLICKPIPES
      KINDS = [ ResourceMap::KIND_DATABASE ].freeze
      PIPE_KINDS = [ ResourceMap::KIND_PIPELINE ].freeze
      ALL_KINDS = [ *KINDS, *PIPE_KINDS ].freeze
      DETAILS = Capabilities::Clickhouse::DETAILS
      ORGANIZATION = Capabilities::Clickhouse::ORGANIZATION
      SERVICE = Capabilities::Clickhouse::SERVICE

      def initialize(...)
        super
        @resources = []
        @links = []
        @endpoints = []
        @undescribed = 0
      end

      # Everything the connection reaches, or with scope the one service a change named (MapEventSources::Clickhouse),
      # read again with its ClickPipes. nil for a scope it cannot narrow to, which a sweep reads.
      def map(scope: nil)
        return narrowed(scope) if scope

        services_by_organization(gaps: true)&.each do |organization, services|
          services.each { |service| service(organization, service) }
        end
        undescribed_gap
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps, endpoints: @endpoints)
      end

      # Each organization with its services, for the map and for following changes. For the map an organization whose
      # services could not be read is a gap and left out. With gaps false, for a poll, a refusal raises Refused with
      # ClickHouse's words and a tool switched off answers nil, since only a whole list says a service is gone.
      def services_by_organization(gaps: false)
        organizations = gaps ? read(LIST_ORGANIZATIONS, "organizations", {}) : strict(LIST_ORGANIZATIONS, "organizations", {})
        listed = organizations&.map do |organization|
          what = "services in #{organization['name'] || organization['id']}"
          arguments = { ORGANIZATION => organization["id"] }
          [ organization, gaps ? read(LIST_SERVICES, what, arguments) : strict(LIST_SERVICES, what, arguments) ]
        end
        return listed&.select(&:last) if gaps

        listed if listed&.all?(&:last)
      end

      # A service's ClickPipes, or nil when list_clickpipes is off. A refusal raises Refused, for a poll.
      def clickpipes(organization_id, service_id) = strict(LIST_CLICKPIPES, "ClickPipes of #{service_id}", { ORGANIZATION => organization_id, SERVICE => service_id })

      # Where a ClickPipe reads from: the one source the ClickPipeSource object sets, with its own type where it has one,
      # such as confluent for a Kafka source.
      def self.source_of(pipe)
        kind, source = pipe["source"].to_h.find { |_kind, value| value.is_a?(Hash) }
        return unless kind

        type = source["type"].presence
        type && type != kind ? "#{kind} (#{type})" : kind
      end

      private

      # The service read with get_service_details under the organization the map has it in, with its ClickPipes, a
      # ClickPipe taken as gone when the service's whole list was read without it. ClickHouse documents no answer for a
      # service that is not there, so a service that cannot be read is left to a sweep.
      def narrowed(scope)
        service_id = scope.external_id.to_s.split("/").first
        return if service_id.blank? || scope.account.blank? || !ALL_KINDS.include?(scope.kind)

        answer = call(DETAILS, { ORGANIZATION => scope.account, SERVICE => service_id }, "service #{service_id}")
        return if answer.nil? || answer["isError"]

        found = unwrapped(Capabilities::Answers.data(answer))
        return unless found.is_a?(Hash) && found["id"].to_s == service_id

        organization = Array(read(LIST_ORGANIZATIONS, "organizations", {})).find { |each| each["id"].to_s == scope.account } || { "id" => scope.account }
        service(organization, found)
        wanted = [ PROVIDER, scope.account, scope.kind, scope.external_id ]
        gone = @resources.none? { |each| each.key == wanted } && gaps.none? { |gap| gap.kinds.include?(scope.kind) } ? [ wanted ] : []
        ResourceMap::Snapshot.new(resources: @resources, links: @links, gaps: gaps, endpoints: @endpoints, gone: gone)
      end

      def service(organization, service)
        return if service["id"].blank?

        found = ResourceMap::Found.new(
          provider: PROVIDER, account: organization["id"].to_s, kind: ResourceMap::KIND_DATABASE, external_id: service["id"].to_s,
          name: service["name"].presence || service["id"].to_s, status: service["state"],
          details: {
            "organization" => organization["name"], "cloud" => service["provider"], "region" => service["region"],
            "version" => service["clickhouseVersion"], "replicas" => service["numReplicas"], "idle_scaling" => service["idleScaling"],
            "read_only" => service["isReadonly"]
          }.compact
        )
        @resources << found
        addresses(organization, service, found)
        pipes(found)
      end

      # The ClickPipes ingesting into a service. A tool switched off is one gap for the whole read, not one a service.
      def pipes(service)
        return if @pipes_off

        result = call(LIST_CLICKPIPES, { ORGANIZATION => service.account, SERVICE => service.external_id })
        if result.nil?
          @pipes_off = true
          return gap("#{LIST_CLICKPIPES} is switched off for #{NAME}, so ClickPipes are not on the map.", kinds: PIPE_KINDS)
        end
        what = "ClickPipes of #{service.name}"
        return gap(Sentence.join("#{NAME} refused to list the #{what}", Capabilities::Answers.text(result).truncate(200)), kinds: PIPE_KINDS) if result["isError"]

        listed = unwrapped(Capabilities::Answers.data(result))
        return gap("#{NAME} answered the #{what} in a shape Firefight does not read.", kinds: PIPE_KINDS) unless listed.is_a?(Array) && listed.all?(Hash)

        listed.each { |pipe| pipe(service, pipe) }
      end

      def pipe(service, pipe)
        return if pipe["id"].blank?

        destination = pipe["destination"].to_h
        found = ResourceMap::Found.new(
          provider: PROVIDER, account: service.account, kind: ResourceMap::KIND_PIPELINE, external_id: "#{service.external_id}/#{pipe['id']}",
          name: "#{service.name}/#{pipe['name'].presence || pipe['id']}", status: pipe["state"].to_s.downcase.presence,
          details: {
            "source" => self.class.source_of(pipe), "destination" => [ destination["database"], destination["table"] ].compact_blank.join(".").presence,
            "replicas" => pipe.dig("scaling", "replicas")
          }.compact
        )
        @resources << found
        @links << ResourceMap::FoundLink.new(from: found.key, to: service.key, relation: ResourceMap::RELATION_PART_OF)
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

        answer = call(DETAILS, { ORGANIZATION => organization["id"], SERVICE => service["id"] }, "where #{service['name'] || service['id']} is reached")
        @describing_refused = answer.nil? || answer["isError"]
        data = @describing_refused ? nil : unwrapped(Capabilities::Answers.data(answer))
        data["endpoints"] if data.is_a?(Hash)
      end

      def undescribed_gap
        return unless @undescribed.positive?

        gap("ClickHouse did not say where #{@undescribed} #{'service'.pluralize(@undescribed)} #{@undescribed == 1 ? 'is' : 'are'} reached" \
            "#{" and #{DETAILS} is switched off" unless on?(DETAILS)}, so settings that name #{@undescribed == 1 ? 'it' : 'them'} are not linked.",
            kinds: [], settings: true)
      end

      # The Cloud API answers inside a result envelope, which the server may pass on or unwrap.
      def unwrapped(data) = data.is_a?(Hash) && data.key?("result") ? data["result"] : data

      # The list a tool answered, from the Cloud API's result envelope or as a bare list, or nil with a gap.
      def read(tool, what, arguments)
        data = unwrapped(listing(tool, what, arguments, kinds: KINDS))
        return data if data.is_a?(Array) && data.all?(Hash)

        gap("ClickHouse answered the #{what} in a shape Firefight does not read.", kinds: KINDS) unless data.nil?
      end

      # The list a tool answered, nil when it is off, raising Refused with ClickHouse's words for a refusal or an answer
      # it cannot read.
      def strict(tool, what, arguments)
        result = call(tool, arguments, what)
        return if result.nil?
        raise Refused, Sentence.join("#{NAME} refused to list the #{what}", Capabilities::Answers.text(result).truncate(300)) if result["isError"]

        data = unwrapped(Capabilities::Answers.data(result))
        raise Refused, "#{NAME} answered the #{what} in a shape Firefight does not read." unless data.is_a?(Array) && data.all?(Hash)

        data
      end
    end
  end
end
