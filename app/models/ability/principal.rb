module Ability
  # The three kinds of thing a grant can attach to, addressed the same way
  # from the dashboard, the API and MCP: a kind and an id. The kind is
  # matched against a fixed list rather than constantized from input.
  module Principal
    KIND_USER = "user"
    KIND_AGENT = "agent"
    KIND_API_KEY = "api_key"
    KINDS = [ KIND_USER, KIND_AGENT, KIND_API_KEY ].freeze

    def self.find!(workspace, kind, id)
      case kind.to_s
      when KIND_USER then workspace.workspace_memberships.find(id)
      when KIND_AGENT then workspace.agents.find(id)
      when KIND_API_KEY then workspace.api_keys.service.find(id)
      else raise ActiveRecord::RecordNotFound, "unknown principal kind #{kind.inspect}"
      end
    end

    # A principal as a rule or an approval stores it: kind plus id. A bare
    # string is a person, which is how approvers were written before agents
    # could be named.
    def self.reference(value)
      return { "kind" => KIND_USER, "id" => value.to_s } if value.is_a?(String)

      value = value.to_h.stringify_keys
      { "kind" => value["kind"].to_s, "id" => value["id"].to_s }
    end

    def self.reference_for(principal)
      { "kind" => principal.actor_kind, "id" => principal.id }
    end

    def self.references(values)
      Array(values).map { |value| reference(value) }.reject { |ref| ref["id"].blank? }.uniq
    end

    def self.find_reference(workspace, reference)
      find!(workspace, reference["kind"], reference["id"])
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # Everyone who can hold a grant, with their grants loaded.
    def self.all(workspace)
      associations = { ability_grants: [ :action, { role: :role_actions } ] }
      memberships = workspace.workspace_memberships.includes(:user, associations)
      agents = workspace.agents.active.includes(associations)
      keys = workspace.api_keys.where(deleted_at: nil).service.includes(associations)
      memberships.to_a + agents.to_a + keys.to_a
    end
  end
end
