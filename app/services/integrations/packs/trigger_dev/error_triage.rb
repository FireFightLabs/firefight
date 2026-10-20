module Integrations
  module Packs
    class TriggerDev
      # Triaging error groups: marking one resolved, ignored or unresolved again (resolve_error_v1, ignore_error_v1,
      # unresolve_error_v1), as Trigger.dev's OpenAPI spec gives them (triggerdotdev/trigger.dev, docs/v3-openapi.yaml).
      # A resolved group that happens again, or an ignored one past its condition, comes back as unresolved and alerts.
      module ErrorTriage
        UNRESOLVED = "unresolved".freeze
        RESOLVED = "resolved".freeze
        IGNORED = "ignored".freeze
        ERROR = { "type" => "string", "description" => "The error group, by its id starting error_, as list_errors shows it" }.freeze

        def self.included(pack)
          pack.tool :resolve_error,
                    summary: "Marks a Trigger.dev error group resolved.",
                    description: "Mark an error group resolved, such as once its fix is deployed. If it happens again it comes back as " \
                                 "unresolved and a Trigger.dev error alert fires",
                    params_schema: { "type" => "object",
                                     "properties" => { "error" => ERROR, "version" => { "type" => "string", "description" => "The version that fixed it, such as 20250228.1 (optional)" } },
                                     "required" => [ "error" ] },
                    read_only: false

          pack.tool :ignore_error,
                    summary: "Marks a Trigger.dev error group ignored, for a while or until it grows.",
                    description: "Mark an error group ignored, for good, for some minutes, or until it happens more than a rate or a count, " \
                                 "such as a known flaky dependency. Past its condition it comes back as unresolved",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "error" => ERROR,
                        "minutes" => { "type" => "integer", "description" => "Ignore it for this many minutes (optional, for good)" },
                        "per_minute" => { "type" => "number", "description" => "Bring it back when it happens more than this many times a minute (optional)" },
                        "occurrences" => { "type" => "integer", "description" => "Bring it back once it happens this many more times (optional)" },
                        "reason" => { "type" => "string", "description" => "Why it is ignored, which Trigger.dev shows beside it (optional)" }
                      },
                      "required" => [ "error" ]
                    },
                    read_only: false

          pack.tool :unresolve_error,
                    summary: "Marks a resolved or ignored Trigger.dev error group unresolved again.",
                    description: "Move a resolved or ignored error group back to unresolved",
                    params_schema: { "type" => "object", "properties" => { "error" => ERROR }, "required" => [ "error" ] },
                    read_only: false
        end

        # The group is named in the answer only when it was unresolved before, so an undo puts back exactly that.
        def resolve_error(environment_row:, arguments:)
          id, before, known = error_before(environment_row, arguments, RESOLVED)
          version = arguments["version"].to_s.strip.presence
          fail!("version is a deployed version, such as 20250228.1.") if version && !version.match?(VERSION)

          group = changing("resolve error #{id}") { api(environment_row).resolve_error(id, version: version) }
          Telemetry.result("#{group_name(known.merge(group.compact), id)} is resolved#{" in version #{version}" if version}, from #{before}. If it happens again it comes " \
                           "back as unresolved. #{no_page}", link: nil, facts: { "error" => (id if before == UNRESOLVED) })
        end

        def ignore_error(environment_row:, arguments:)
          id, before, known = error_before(environment_row, arguments, IGNORED)
          minutes = whole(arguments["minutes"], "minutes")
          occurrences = whole(arguments["occurrences"], "occurrences")
          rate = arguments["per_minute"].presence && Float(arguments["per_minute"], exception: false)
          fail!("per_minute must be a number above 0.") if arguments["per_minute"].present? && !rate&.positive?

          group = changing("ignore error #{id}") do
            api(environment_row).ignore_error(id, duration_ms: (minutes * 60_000 if minutes), occurrence_rate: rate, total_occurrences: occurrences,
                                                  reason: arguments["reason"].to_s.strip.presence)
          end
          until_when = [ ("for #{minutes} minutes" if minutes), ("until it happens more than #{rate} times a minute" if rate),
                         ("until it happens #{occurrences} more times" if occurrences) ].compact
          Telemetry.result("#{group_name(known.merge(group.compact), id)} is ignored #{until_when.any? ? until_when.join(' or ') : 'for good'}, from #{before}. #{no_page}",
                           link: nil, facts: { "error" => (id if before == UNRESOLVED) })
        end

        def unresolve_error(environment_row:, arguments:)
          id, before, known = error_before(environment_row, arguments, UNRESOLVED)
          group = changing("unresolve error #{id}") { api(environment_row).unresolve_error(id) }
          Telemetry.result("#{group_name(known.merge(group.compact), id)} is unresolved again, from #{before}. #{no_page}", link: nil)
        end

        private

        # The group's id and the status it has now, refused when it already has the one asked.
        def error_before(environment_row, arguments, wanted)
          id = arguments["error"].to_s.strip
          fail!("Say which error group, by its id starting error_. list_errors shows them.") if id.empty?

          group = begin
            api(environment_row).error_group(id)
          rescue TriggerDevApi::Error => error
            raise if error.is_a?(Integrations::RateLimited)

            fail!("Trigger.dev could not read error group #{id}: #{error.message}")
          end
          fail!("#{group_name(group, id)} is already #{wanted}.") if group["status"].to_s == wanted

          [ id, group["status"].presence || UNRESOLVED, group ]
        end

        def group_name(group, id) = "Error group #{id} (#{group['errorType'] || 'error'} in #{group['taskIdentifier'] || 'its task'})"

        def whole(value, name)
          return if value.blank?

          # Integer() truncates a Float, so a fraction is refused rather than rounded down.
          count = value.is_a?(Float) && !(value.finite? && value == value.floor) ? nil : Integer(value, exception: false)
          fail!("#{name} must be a whole number above 0.") unless count&.positive?

          count
        end
      end
    end
  end
end
