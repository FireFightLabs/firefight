# An AI subscription a workspace can connect on the AI accounts card, and how its sign-in goes.
class AiSubscriptionOptionSerializer < BaseSerializer
  object_as :subscription

  attributes(key: { type: :string }, name: { type: :string }, plan: { type: :string })

  # The person enters a code on the provider's page, rather than pasting back an address.
  type :boolean
  def device = subscription.device?

  # Where the person signs in, when there is more than one place to choose from.
  type "{ proxy: string; label: string | null }[]"
  def sites = subscription.sites.map { |site| { proxy: site.proxy, label: site.label } }

  # Why it cannot be connected right now, or nil.
  type :string, optional: true
  def blocked_reason = (SubscriptionProxy::UNAVAILABLE unless SubscriptionProxy.usable?)
end
