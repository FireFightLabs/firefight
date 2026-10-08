# Reads every provider documentation source into the docs store once a day, then embeds the chunks whose words changed.
# A source that fails keeps the copy it had and the rest carry on. unread_only reads only the sources never read yet,
# which a fresh install asks for when its job runner starts, so the store fills in the background on first boot.
class ProviderDocsSyncJob < ApplicationJob
  queue_as :background
  limits_concurrency key: "provider_docs_sync", duration: 6.hours

  def perform(unread_only = false)
    keys = unread_only ? ProviderDocSource.unread_keys : nil
    return if keys&.empty?

    client = DocsClient.new
    ProviderDocSource::Definition.all.each do |definition|
      next if keys && !keys.include?(definition.key)

      read(definition, client)
    end
    embed
    note_missing_guides
  end

  private

  def read(definition, client)
    source = ProviderDocs::Sync.run!(definition, client: client)
    Rails.logger.info({ event: "provider_docs.read", source: definition.key, pages: source.page_count, version: source.version, failed: source.error.present? }.to_json)
  rescue DocsClient::Error, SystemCallError, JSON::ParserError, KeyError => error
    Rails.logger.warn({ event: "provider_docs.unread", source: definition.key, error: error.message.truncate(300) }.to_json)
  end

  def embed
    written = ProviderDocs::Embedding.run!
    Rails.logger.info({ event: "provider_docs.embedded", chunks: written }.to_json)
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "provider_docs.unembedded", error: error.message.truncate(300) }.to_json)
  end

  # A guide a skill lists that its provider's documentation no longer holds, so whoever runs Firefight sees it moved.
  def note_missing_guides
    missing = Chat::Skill.missing_references
    Rails.logger.warn({ event: "provider_docs.missing_guides", guides: missing }.to_json) if missing.any?
  end
end
