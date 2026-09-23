# One provider in an integrations card, and where it stands in this workspace.
class IntegrationCardRowSerializer < BaseSerializer
  object_as :row

  STATE_UNION = IntegrationProvider::STATES.map(&:inspect).join(" | ")

  has_one :provider, serializer: IntegrationProviderSerializer

  type STATE_UNION
  def state
    row.state
  end

  type :string
  def stateLabel
    row.state_label
  end

  type IntegrationProvider::ACTIONS.map(&:inspect).join(" | ")
  def action
    row.action
  end

  type :string
  def actionLabel
    row.action_label
  end

  type "{ id: string; name: string }[]"
  def connections
    row.connections
  end
end
