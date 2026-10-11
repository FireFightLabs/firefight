# Reads every provider documentation source into the docs store once a day, then embeds the chunks whose words changed.
# A source that fails keeps the copy it had and the rest carry on. unread_only reads only the sources never read yet,
# which a fresh install asks for when its job runner starts, so the store fills in the background on first boot. source
# reads that one source alone, and progress says what the run is doing as it goes (bin/rails provider_docs:sync).
class ProviderDocsSyncJob < ApplicationJob
  queue_as :background
  limits_concurrency key: "provider_docs_sync", duration: 6.hours

  def perform(unread_only = false, source: nil, progress: ProviderDocs::Progress.new)
    keys = unread_only ? ProviderDocSource.unread_keys : nil
    return if keys&.empty?

    definitions = ProviderDocSource::Definition.all.select { |definition| (keys.nil? || keys.include?(definition.key)) && (source.nil? || definition.key == source) }
    return if definitions.empty?

    progress.started(definitions.map(&:key))
    client = DocsClient.new
    definitions.each { |definition| read(definition, client, progress) }
    embed(progress)
    note_missing_guides(progress)
    note_stale_indexes(progress)
    progress.finished
  end

  private

  # Sync has already recorded and reported why a source could not be read.
  def read(definition, client, progress)
    ProviderDocs::Sync.run!(definition, client: client, progress: progress)
  rescue *ProviderDocs::Sync::READ_ERRORS
    nil
  end

  def embed(progress)
    ProviderDocs::Embedding.run!(progress: progress)
  rescue FirefightAi::Error => error
    progress.embedding_failed(error)
  end

  # A guide a skill lists that its provider's documentation no longer holds, so whoever runs Firefight sees it moved.
  def note_missing_guides(progress)
    missing = Chat::Skill.missing_references
    progress.missing_guides(missing) if missing.any?
  end

  # A key read an API index lists that the reference just read no longer does, so whoever runs Firefight replaces it
  # (bin/rails provider_docs:api_indexes) before Halon is sent to a path that is gone.
  def note_stale_indexes(progress)
    stale = Integrations::ApiIndex::Refresh.stale
    progress.stale_api_indexes(stale) if stale.any?
  end
end
