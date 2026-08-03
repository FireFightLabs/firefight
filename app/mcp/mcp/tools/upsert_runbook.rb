module Mcp
  module Tools
    class UpsertRunbook < Base
      tool_name UPSERT_RUNBOOK
      description "Create or update an incident response runbook. Pass slug to update an " \
                  "existing runbook (steps/conditions replace the current set when given); " \
                  "omit it to create one (name required). Attach conditions auto-attach the " \
                  "runbook to matching incidents. If the call requires approval, retry the " \
                  "identical call with approval_id once approved. Docs: #{Docs::RUNBOOKS}"
      annotations(**WRITE)
      input_schema(
        properties: {
          slug: { type: "string", description: "Existing runbook slug to update; omit to create" },
          name: { type: "string", description: "Runbook name (required on create)" },
          summary: { type: "string", description: "One-line summary shown in search results" },
          content: { type: "string", description: "Full runbook content (markdown)" },
          external_url: { type: "string", description: "Link to an external doc, if any" },
          steps: {
            type: "array",
            description: "Ordered steps, e.g. [{\"title\": \"...\", \"instruction\": \"...\"}]; replaces existing steps",
            items: { type: "object" }
          },
          conditions: {
            type: "array",
            description: "Attach conditions, e.g. [{\"condition_field\": \"severity\", \"operator\": \"one_of\", \"values\": [\"critical\"]}]. " \
                         "severity and incident_type values accept slugs or ids; custom_field values are option ids. Replaces existing conditions",
            items: { type: "object" }
          },
          approval_id: { type: "string", description: "Approval id when retrying an approved call" }
        },
        required: []
      )

      def self.authorization(workspace, args)
        [ ApiKey::RESOURCE_RUNBOOKS, existing_runbook(workspace, args) ? ApiKey::ACTION_UPDATE : ApiKey::ACTION_CREATE ]
      end

      def self.perform(workspace:, args:)
        runbook = existing_runbook(workspace, args)

        Runbook.transaction do
          if runbook
            runbook.update!(runbook_attributes(args))
          else
            runbook = workspace.runbooks.create!(name: args[:name].to_s, **runbook_attributes(args))
          end

          runbook.sync_steps!(step_params(args)) if args.key?(:steps)
          runbook.sync_conditions!(condition_params(workspace, args)) if args.key?(:conditions)
        end

        respond(
          slug: runbook.slug, name: runbook.name, summary: runbook.summary,
          steps_count: runbook.runbook_steps.count, conditions_count: runbook.incident_conditions.count
        )
      end

      def self.existing_runbook(workspace, args)
        return nil if args[:slug].blank?

        workspace.runbooks.active.find_by(slug: args[:slug].to_s)
      end

      def self.runbook_attributes(args)
        { name: args[:name], summary: args[:summary], content: args[:content],
          external_url: args[:external_url] }.compact
      end

      def self.step_params(args)
        Array(args[:steps]).map do |step|
          step = step.to_h.with_indifferent_access
          { title: step[:title], instruction: step[:instruction] }
        end
      end

      def self.condition_params(workspace, args)
        Array(args[:conditions]).map do |condition|
          condition = condition.to_h.with_indifferent_access
          { condition_field: condition[:condition_field], operator: condition[:operator],
            values: resolve_values(workspace, condition),
            incident_field_definition_id: condition[:incident_field_definition_id] }
        end
      end

      # Conditions match on ids, but an agent knows slugs. Accept either, and
      # refuse anything that resolves to neither: a stored value that matches no
      # record produces a runbook that saves cleanly and then never attaches.
      def self.resolve_values(workspace, condition)
        values = Array(condition[:values]).map(&:to_s)
        scope = condition_scope(workspace, condition[:condition_field])
        return values unless scope

        by_slug = scope.pluck(:slug, :id).to_h
        known_ids = by_slug.values.to_set

        values.map do |value|
          next value if known_ids.include?(value)
          next by_slug[value] if by_slug.key?(value)

          raise ArgumentError,
            "unknown #{condition[:condition_field]} #{value.inspect}. Valid: #{by_slug.keys.sort.join(', ')}"
        end
      end

      def self.condition_scope(workspace, condition_field)
        case condition_field
        when IncidentCondition::FIELD_SEVERITY      then workspace.incident_severities.active
        when IncidentCondition::FIELD_INCIDENT_TYPE then workspace.incident_types.active
        end
      end
    end
  end
end
