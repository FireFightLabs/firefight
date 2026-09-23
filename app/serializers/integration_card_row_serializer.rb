# One provider in an integrations card, and where it stands in this workspace.
class IntegrationCardRowSerializer < BaseSerializer
  object_as :row

  STATE_UNION = IntegrationProvider::STATES.map(&:inspect).join(" | ")

  has_one :provider, serializer: IntegrationProviderSerializer

  type STATE_UNION
  def state
    row.state
  end

  type "{ id: string; name: string }[]"
  def connections
    row.connections
  end
end
