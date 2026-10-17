# Something an entry of what Halon may do without asking can name, a capability with the connections that make it, or
# one connection's tool.
class AllowanceChoiceSerializer < BaseSerializer
  object_as :choice

  type :string
  def value = choice.value

  type :string
  def label = choice.label

  type "{ value: string, label: string }[]"
  def connections = choice.connections.map { |connection| { value: connection.value, label: connection.label } }
end
