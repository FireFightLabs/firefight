module Ability
  # What a principal can actually do, for the settings UI and debugging denials.
  module Preview
    def self.for(principal)
      resolved = Resolver.resolve(principal)
      actions = Action.where(workspace_id: [ nil, principal.workspace_id ], key: resolved.action_keys)
                      .index_by(&:key)

      resolved.by_key.map do |key, scopes|
        action = actions[key]
        { action_key: key, risk_level: action&.risk_level, reversible: action&.reversible, scopes: scopes }
      end.sort_by { |ability| ability[:action_key] }
    end

    def self.implicit_member_reads
      Action.system_actions.grantable.where(risk_level: Action::RISK_READ).order(:key).map do |action|
        { action_key: action.key, risk_level: action.risk_level, reversible: action.reversible,
          scopes: [ {} ], implicit: true }
      end
    end
  end
end
