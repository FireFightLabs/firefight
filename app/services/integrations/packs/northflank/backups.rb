module Integrations
  module Packs
    class Northflank < NativePack
      # A database's backups as run history, so a watch follows a backup to its end and learns how long one usually takes
      # (GetAddonBackupsResult and GetAddonBackupResult: status, createdAt, completedAt).
      module Backups
        BACKUP_HISTORY = "backup_history".freeze
        BACKUP_LIMIT = 20
        History = Capabilities::History
        STATUSES = {
          "scheduled" => History::QUEUED, "in-progress" => History::RUNNING, "aborting" => History::RUNNING,
          "completed" => History::SUCCEEDED, "failed" => History::FAILED, "not-supported" => History::FAILED, "aborted" => History::CANCELLED
        }.freeze

        def self.included(pack)
          pack.tool BACKUP_HISTORY,
                    description: "A Northflank database's recent backups, newest first, each with its status, when it started and finished " \
                                 "and how long it took, and how long finished ones usually take. Name a backup to read it alone",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => RESOURCE,
                        "name" => { "type" => "string", "description" => "Only runs of this kind, backup (optional)" },
                        "run" => { "type" => "string", "description" => "Only this backup, by its id (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many backups (optional, #{BACKUP_LIMIT})" }
                      },
                      "required" => [ "resource" ]
                    },
                    read_only: true
        end

        def backup_history(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"])
          fail! "#{resource[:name]} is a #{KIND_NOUNS.fetch(resource[:kind])}, and only databases have backups." unless resource[:kind] == KIND_ADDONS

          project = project_of(environment_row)
          backups = if arguments["run"].present?
            [ api(environment_row).backup(project, resource[:id], arguments["run"].to_s.strip) ].compact_blank
          else
            api(environment_row).backups(project, resource[:id], limit: limit(arguments, BACKUP_LIMIT))
          end
          runs = backups.map { |backup| backup_run(backup) }
          History.result(runs, what: "the backups of #{resource[:name]}", link: resource_link(environment_row, resource), name: arguments["name"],
                               limit: limit(arguments, BACKUP_LIMIT))
        rescue NorthflankApi::NotFound
          fail! "#{resource[:name]} has no backup #{arguments['run']}. backup_history lists its backups."
        end

        def backup_run(backup)
          status = History.status(backup["status"], STATUSES)
          History::Run.new(
            id: backup["id"].to_s, name: "backup", status: status, started_at: Telemetry.parse_time(backup["createdAt"]),
            finished_at: (Telemetry.parse_time(backup["completedAt"]) if History::FINISHED.include?(status)),
            detail: [ backup["name"].presence, backup.dig("config", "source", "type").presence, ("not supported" if backup["status"] == "not-supported") ].compact.join(", ").presence
          )
        end
      end
    end
  end
end
