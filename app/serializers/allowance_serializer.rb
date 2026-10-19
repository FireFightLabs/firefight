# One entry of what Halon may do without asking, shaped as a settings row (ConfigurableOption), with its sentence as the
# name, whether it is on, and why it cannot be deleted once Halon acted under it.
class AllowanceSerializer < BaseSerializer
  object_as :allowance

  type :string
  def id = allowance.id

  # The entry as a person reads it, such as "Roll back deploys in Staging".
  type :string
  def name = allowance.sentence

  type :string, optional: true
  def capability = allowance.capability

  type :string, optional: true
  def action_key = allowance.action&.key

  # The connection a capability is kept to, by its slug.
  type :string, optional: true
  def integration = allowance.integration&.slug

  type :string, optional: true
  def environment_id = allowance.environment_id

  attributes(enabled: { type: :boolean })

  # How many changes Halon made under it.
  type :number
  def usage_count = allowance.usage_count

  type :string, optional: true
  def created_by_name = allowance.created_by&.display_name

  type :string, optional: true
  def deletion_blocked_reason = allowance.delete_blocked_reason
end
