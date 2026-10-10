# A connection handbook pages can be synced from. A code host comes with the repositories the map shows it holds, and a
# tool that keeps documents comes alone.
class HandbookImporterSerializer < BaseSerializer
  object_as :integration

  type :string
  def id = integration.id

  type :string
  def name = integration.name

  type "'repository' | 'document'"
  def kind = Integrations::RepositoryDocuments.reads?(integration) ? Chat::HandbookSource::KIND_REPOSITORY : Chat::HandbookSource::KIND_DOCUMENT

  # Repositories on the map this connection reports that the viewer may see, by full name.
  type "string[]"
  def repositories
    return [] unless kind == Chat::HandbookSource::KIND_REPOSITORY

    ResourceMap::Resource.visible_to(options[:principal], integration.workspace).present
                         .where(kind: ResourceMap::KIND_REPOSITORY, integration_environment_id: integration.integration_environments.select(:id))
                         .order(:name).pluck(:external_id).uniq
  end
end
