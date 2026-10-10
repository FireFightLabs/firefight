# Something on the map an unattended rule can name, with the changes a connection holding it can make.
class UnattendedRuleResourceSerializer < BaseSerializer
  object_as :choice

  type :string
  def id = choice.resource.id

  type :string
  def name = choice.resource.name

  type "ResourceMapKind"
  def kind = choice.resource.kind

  type "(#{UnattendedRuleSerializer::CAPABILITY_UNION})[]"
  def capabilities = choice.capabilities
end
