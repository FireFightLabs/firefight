# One category of integrations as the chat draws it. Where each provider stands is decided here, never on the page.
class IntegrationCardSerializer < BaseSerializer
  object_as :card

  type :string
  def category
    card.category.slug
  end

  type :string
  def name
    card.category.name
  end

  type :string
  def tagline
    card.category.tagline
  end

  has_many :rows, serializer: IntegrationCardRowSerializer
end
