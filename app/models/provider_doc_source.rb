# One documentation source config/provider_docs.yml lists, as the daily refresh last found it. Its pages are replaced
# only by a refresh that read them, so a source that cannot be read keeps the copy it had, with error saying why.
class ProviderDocSource < ApplicationRecord
  has_many :pages, class_name: "ProviderDocPage", inverse_of: :source, dependent: :delete_all

  scope :read, -> { where.not(fetched_at: nil) }

  # Whether a provider's documentation has ever been read here, so a missing page is told apart from a store not filled yet.
  def self.read_for?(provider) = read.exists?(provider: provider.to_s)

  # The sources never read yet, which a fresh install fills first.
  def self.unread_keys = Definition.all.map(&:key) - read.pluck(:key)

  def self.for(definition) = find_or_create_by!(key: definition.key) { |source| source.provider = definition.provider }

  def definition = Definition.find(key)

  # A refresh that could not read the source keeps every page it had and says why.
  def failed!(message, at: Time.current) = update!(error: message.to_s.truncate(1_000), checked_at: at)
end
