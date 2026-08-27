module Mcp
  module Tools
    class ListAbilities < Base
      tool_name LIST_ABILITIES
      description "Every ability that can be granted in this workspace: Firefight's own settings " \
                  "plus the capabilities enabled on connected tools, with risk level and whether an " \
                  "approval rule can hold it. Use the key with grant_ability and upsert_approval_rule. " \
                  "Docs: #{Docs::PERMISSIONS}"
      annotations(**READ_ONLY)
      authorize_as Ability::Action::RESOURCE_PERMISSIONS
      input_schema(
        properties: {
          query: { type: "string", description: "Substring of the ability key, e.g. runbooks or planetscale" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        scope = Ability::Grant.grantable_actions(workspace)
        scope = scope.where("key ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(args[:query].to_s)}%") if args[:query].present?

        respond(abilities: scope.map do |action|
          {
            key: action.key, kind: action.kind, risk_level: action.risk_level, reversible: action.reversible,
            group: action.system? ? "Firefight" : action.source&.integration&.name.to_s,
            approval_exempt: Ability::Action.approval_exempt?(action.key)
          }
        end)
      end
    end
  end
end
