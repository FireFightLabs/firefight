module Integrations
  module MapEventSources
    # ClickHouse Cloud sends no events Firefight can register for, and its remote MCP server offers no activity log, so
    # every five minutes Firefight lists each organization's services with get_services_list and each service's
    # ClickPipes with list_clickpipes, through the tools ClickHouse documents for that server, only those an admin
    # switched on, each call recorded under the map sweep. A service whose state or whose ClickPipes' states changed
    # since the last read is read again, with its ClickPipes.
    class Clickhouse < MapEventSource
      NO_TOOL = "This ClickHouse server offers no tool that lists an organization's services, which following its changes needs".freeze
      SWITCHED_OFF = "get_organizations or get_services_list is switched off for ClickHouse, and following its changes reads each " \
                     "organization's services through them".freeze

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def limits = "Firefight reads each service's state and its ClickPipes' states every 5 minutes, so a change reaches the map within about " \
                     "6 minutes. A change to a service's settings or a ClickPipe's source reaches the map at each hourly sweep."

        # The cursor holds each service's fingerprint by id. The first read only takes them, so changes are followed from
        # then. A service is taken as removed only when every organization's whole list was read without it.
        def poll(row, since:)
          raise Integrations::Error, NO_TOOL unless row.integration.tools.available.exists?(name: MapReaders::Clickhouse::LIST_SERVICES)

          reader = McpExecutor.map_events_reader(row)
          listed = reader.services_by_organization
          raise Integrations::Error, SWITCHED_OFF if listed.nil?

          before = cursor_of(since)
          now = listed.each_with_object({}) do |(organization, services), fingerprints|
            services.each do |service|
              next if service["id"].blank?

              id = service["id"].to_s
              pipes = reader.clickpipes(organization["id"], service["id"])
              # A ClickPipe list not read this time keeps the last one, so a removal during the gap is still followed.
              ids = pipes ? pipes.filter_map { |pipe| pipe["id"].presence&.to_s }.sort : before&.dig(id, "pipes")
              fingerprints[id] = { "account" => organization["id"].to_s, "print" => fingerprint(service, pipes), "pipes" => ids }.compact
            end
          end
          MapEventSource::Polled.new(events: before ? changes(before, now) : [], cursor: { "services" => now }.to_json)
        rescue RemoteReader::Refused => error
          raise MapEventSource::Refused, error.message
        end

        private

        def cursor_of(since)
          return if since.blank?

          parsed = JSON.parse(since)
          parsed["services"] if parsed.is_a?(Hash) && parsed["services"].is_a?(Hash)
        rescue JSON::ParserError
          nil
        end

        def changes(before, now)
          events = now.filter_map do |id, seen|
            if !before.key?(id)
              event(id, seen, ResourceMap::Event::ADDED)
            elsif before[id]["print"] != seen["print"]
              event(id, seen, ResourceMap::Event::UPDATED)
            end
          end
          events + (before.keys - now.keys).map { |id| event(id, before[id].merge("print" => "gone-#{before[id]['print']}"), ResourceMap::Event::REMOVED) } +
            pipes_removed(before, now)
        end

        # A ClickPipe a service's whole list had last time and has no longer is its own removal, since a re-read of the
        # service only takes away what lies within the service's scope.
        def pipes_removed(before, now)
          now.flat_map do |id, seen|
            was = before.dig(id, "pipes")
            next [] unless was.is_a?(Array) && seen["pipes"]

            (was - seen["pipes"]).map do |pipe|
              ResourceMap::Event.new(id: "#{id}/#{pipe}@gone-#{seen['print']}", at: Time.current, action: ResourceMap::Event::REMOVED,
                                     scope: ResourceMap::Scope.new(account: seen["account"], kind: ResourceMap::KIND_PIPELINE, external_id: "#{id}/#{pipe}"))
            end
          end
        end

        # A service's state and its ClickPipes' states, from the Service and ClickPipe objects. ClickPipes are left out when
        # list_clickpipes is off.
        def fingerprint(service, pipes)
          parts = Array(pipes).map { |pipe| [ pipe["id"], pipe["state"] ].join(":") }.sort
          Digest::SHA256.hexdigest([ service["state"], *parts ].to_json).first(16)
        end

        def event(id, seen, action)
          ResourceMap::Event.new(id: "#{id}@#{seen['print']}", at: Time.current, action: action,
                                 scope: ResourceMap::Scope.new(account: seen["account"], kind: ResourceMap::KIND_DATABASE, external_id: id))
        end
      end
    end
  end
end
