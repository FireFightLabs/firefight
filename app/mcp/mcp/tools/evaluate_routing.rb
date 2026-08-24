module Mcp
  module Tools
    class EvaluateRouting < Base
      tool_name EVALUATE_ROUTING
      authorize_as Ability::Action::RESOURCE_POLICIES
      description "Dry-run alert routing: given hypothetical alert fields (e.g. service, " \
                  "event, severity), returns which rule would match, the outcome (create " \
                  "incident / notify / drop), and a per-condition trace. Pure evaluation — " \
                  "nothing is created or sent. Pass source to test that source's routing; " \
                  "omit it for the workspace default. Docs: #{Docs::ROUTING_RULES}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          source: { type: "string", description: "Alert source name; omit for workspace default routing" },
          fields: {
            type: "object",
            description: "The alert fields to evaluate, e.g. {\"service\": \"checkout\", \"event\": \"container:crash\"}",
            additionalProperties: { type: "string" }
          }
        },
        required: [ "fields" ]
      )

      def self.perform(workspace:, args:)
        scope =
          if args[:source].present?
            workspace.alert_sources.find_by(name: args[:source]).tap do |source|
              raise ActiveRecord::RecordNotFound unless source
            end
          else
            workspace
          end
        raw_fields = (args[:fields] || {}).transform_keys(&:to_s).transform_values(&:to_s)
        routed = Alert::Router.new(workspace, scope).route(raw_fields)
        unless routed
          return Mcp::ToolDispatcher.error_response("No enabled alert routing policy configured for this scope. " \
                                                    "Routing rules are documented at #{Docs::ROUTING_RULES}")
        end

        payload = {
          matched: routed.matched?,
          matched_rule_priority: routed.matched_rule&.priority,
          outcome: enriched_outcome(workspace, routed.outcome),
          context: routed.context,
          trace: routed.trace
        }
        payload[:docs_url] = Docs::ROUTING_RULES unless routed.matched?
        role_warnings = Alert::RoutingRoleGaps.for(workspace)
        payload[:role_warnings] = role_warnings if role_warnings.any?
        respond(payload)
      end

      # Outcome targets store bare IDs. Resolve display names at read time so
      # MCP clients see who is notified/invited, not opaque UUIDs. Channel
      # names are stored on the target at config time and pass through as-is.
      def self.enriched_outcome(workspace, outcome)
        return outcome unless outcome.is_a?(Hash)

        outcome = outcome.deep_dup
        if outcome["severity_id"].present?
          severity = workspace.incident_severities.find_by(id: outcome["severity_id"])
          outcome["severity_name"] = severity.name if severity
        end
        outcome["notify"] = enriched_target(workspace, outcome["notify"])
        outcome["invite"] = outcome["invite"].map { |target| enriched_target(workspace, target) } if outcome["invite"].is_a?(Array)
        outcome.compact
      end

      def self.enriched_target(workspace, target)
        return target unless target.is_a?(Hash)

        case target["type"]
        when PolicyRule::AlertRoutingOutcome::TARGET_MEMBER
          member = workspace.workspace_memberships.find_by(id: target["member_id"])
          member ? target.merge("member_name" => member.display_name) : target
        when PolicyRule::AlertRoutingOutcome::TARGET_TEAM
          entry = workspace.catalog_entries.active.find_by(id: target["entry_id"])
          entry ? target.merge("entry_name" => entry.name, "entry_slug" => entry.slug) : target
        else
          target
        end
      end
    end
  end
end
