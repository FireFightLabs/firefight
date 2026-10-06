module Integrations
  module MapEventSources
    # Neon sends no events Firefight can register for, so every five minutes it reads the operations of each project the
    # map has from this connection (Neon API, GET /projects/{project_id}/operations), through the list_operations tool
    # Neon's own server offers (neondatabase/mcp-server-neon, mcp/tools/generated/names.ts, operations.list), only when an
    # admin switched it on, each call recorded under the map sweep. An operation names the project, branch and compute it
    # is about, and the project is read again. A server that offers no such tool leaves the connection on the hourly read,
    # saying why.
    class Neon < MapEventSource
      # Operations are written as they run, so each read looks back this far, and one read twice is kept once.
      LAG = 2.minutes
      # The operations that change what the map shows of a branch or compute, from Neon's OperationAction list. The rest
      # are Neon's own upkeep.
      ACTIONS = %w[
        create_compute start_compute suspend_compute apply_config create_branch create_timeline delete_timeline timeline_archive
        timeline_unarchive detach_parent_branch sync_dbs_and_roles_from_compute apply_schema_from_branch promote_replica
        start_reserved_compute import_data
      ].freeze
      ADDED = %w[create_compute create_branch create_timeline].freeze
      REMOVED = %w[delete_timeline].freeze
      # An operation that ended, from Neon's OperationStatus list.
      ENDED = %w[finished failed error].freeze
      NO_TOOL = "This Neon server offers no tool that lists a project's operations, which following its changes needs".freeze
      SWITCHED_OFF = "list_operations is switched off for Neon, and following its changes reads each project's operations through it".freeze

      class << self
        def verify(**) = false

        def events(_payload, headers:) = []

        def poll(row, since:)
          raise Integrations::Error, NO_TOOL unless row.integration.tools.available.exists?(name: MapReaders::Neon::LIST_OPERATIONS)

          now = Time.current
          return MapEventSource::Polled.new(events: [], cursor: now.utc.iso8601) if since.blank?

          from = start_of(since, now)
          reader = McpExecutor.map_events_reader(row)
          events = projects_of(row).flat_map do |account, project_id|
            operations = reader.operations(project_id)
            raise Integrations::Error, SWITCHED_OFF if operations.nil?

            project_events(account, project_id, operations, from)
          end
          MapEventSource::Polled.new(events: events, cursor: now.utc.iso8601)
        rescue RemoteReader::Refused => error
          raise MapEventSource::Refused, error.message
        end

        private

        def start_of(since, now)
          Time.iso8601(since) - LAG
        rescue ArgumentError
          now - LAG
        end

        # The projects the map has from this connection, under the account it has each in.
        def projects_of(row)
          ResourceMap::Resource.where(integration_environment_id: row.id, provider: MapReaders::Neon::PROVIDER, kind: ResourceMap::KIND_DATABASE, removed_at: nil)
                               .pluck(:account, :external_id)
        end

        # An operation that ended since from, about the compute or branch it names, else the project. A full page whose
        # every operation is that recent may have left some out, so the project is read again too.
        def project_events(account, project_id, operations, from)
          recent = operations.select { |operation| changed_at(operation) && changed_at(operation) >= from }
          events = recent.select { |operation| ACTIONS.include?(operation["action"]) && ENDED.include?(operation["status"]) }.map do |operation|
            ResourceMap::Event.new(id: "#{operation['id']}:#{operation['status']}", at: changed_at(operation), action: action_of(operation["action"]),
                                   scope: scope_of(account, project_id, operation))
          end
          if operations.size >= MapReaders::Neon::OPERATION_LIMIT && recent.size == operations.size
            events << ResourceMap::Event.new(id: "#{project_id}:page@#{recent.filter_map { |operation| changed_at(operation) }.max.to_i}", at: Time.current,
                                             action: ResourceMap::Event::UPDATED,
                                             scope: ResourceMap::Scope.new(account: account, kind: ResourceMap::KIND_DATABASE, external_id: project_id))
          end
          events
        end

        def changed_at(operation)
          Time.iso8601(operation["updated_at"].to_s)
        rescue ArgumentError
          nil
        end

        def action_of(action)
          return ResourceMap::Event::ADDED if ADDED.include?(action)
          return ResourceMap::Event::REMOVED if REMOVED.include?(action)

          ResourceMap::Event::UPDATED
        end

        def scope_of(account, project_id, operation)
          kind, id = if operation["endpoint_id"].present? then [ ResourceMap::KIND_COMPUTE, "#{project_id}/#{operation['endpoint_id']}" ]
          elsif operation["branch_id"].present? then [ ResourceMap::KIND_BRANCH, "#{project_id}/#{operation['branch_id']}" ]
          else [ ResourceMap::KIND_DATABASE, project_id ]
          end
          ResourceMap::Scope.new(account: account, kind: kind, external_id: id)
        end
      end
    end
  end
end
