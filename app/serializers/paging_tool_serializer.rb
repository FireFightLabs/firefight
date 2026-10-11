# A connection Halon pages through, as the on-call page shows it: whether Firefight can page and keep pages in step
# through it, and whether what people do to a page there comes back here.
class PagingToolSerializer < BaseSerializer
  object_as :integration

  type :string
  def id = integration.id

  type :string
  def name = integration.display_name

  type :string
  def provider_key = integration.provider

  type :string
  def mark = entry&.mark || integration.provider.first(2).upcase

  type :string
  def color = entry&.color || "var(--border-strong)"

  # What a page goes to in the tool.
  type :string
  def pages = Integrations::Paging.pages_words(integration.provider).to_s

  # Why Firefight cannot page through it or keep its pages in step, or null.
  type :string, optional: true
  def blocked_reason = integration.workspace.paging_blocked_reason(integration)

  # Why granting again would not help, or null when it gives Firefight paging back what it lost.
  type :string, optional: true
  def grant_blocked_reason = integration.workspace.paging_grant_blocked_reason(integration)

  # The alert source that brings back acknowledgements, notes and resolves made in the tool, or null.
  type :string, optional: true
  def return_source = integration.workspace.paging_return_source(integration)&.name

  # The provider's own name, for the sentence saying which kind of alert source brings changes back.
  type :string
  def provider_name = entry&.name || integration.provider

  # When the provider ends support for the product, or null.
  type :string, optional: true
  def retiring = entry&.retiring

  private

  def entry = IntegrationProvider.find(integration.provider)
end
