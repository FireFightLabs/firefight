class AgentSerializer < BaseSerializer
  object_as :agent

  attributes(
    id: { type: :string },
    name: { type: :string },
    slug: { type: :string },
    enabled: { type: :boolean }
  )

  type :string, optional: true
  def description
    agent.description.presence
  end

  # Every live token, not a count. Rotation leaves two, and whoever rotated
  # needs to see which is which before revoking the old one.
  type "{ id: string; prefix: string; createdAt: string; lastUsedAt: string | null }[]"
  def tokens
    agent.live_api_keys.map do |key|
      {
        id: key.id,
        prefix: key.token_prefix,
        createdAt: key.created_at.utc.iso8601,
        lastUsedAt: key.last_used_at&.utc&.iso8601
      }
    end
  end

  type :string, optional: true
  def last_used_at
    agent.last_used_at&.utc&.iso8601
  end

  # How many abilities it holds. An agent with none can authenticate and do
  # nothing, which is the state worth seeing at a glance.
  type :number
  def grant_count
    agent.ability_grants.size
  end
end
