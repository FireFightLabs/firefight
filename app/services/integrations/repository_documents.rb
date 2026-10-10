module Integrations
  # Text files read from a repository on a connected code host, which the handbook syncs pages from. A code host's pack
  # answers repository_documents(environment_row, repository:, path:) with a CodeHost::Documents::Read, and its event
  # source may answer branch_pushes(payload, headers:) with Pushes, so a push to a default branch syncs the pages read
  # from it at once. Nothing here names a host.
  module RepositoryDocuments
    Push = Data.define(:repository, :branch)

    module_function

    def reads?(integration)
      pack = NativePack.for(integration.provider)
      pack.present? && pack.method_defined?(:repository_documents)
    end

    # Raises Integrations::Error with the host's words when the repository or path cannot be read.
    def read(integration, repository:, path:)
      row = integration.resolve_environment(nil) || integration.integration_environments.enabled.first
      raise Error, "#{integration.name} has no enabled connection to read #{repository} through." unless row

      NativePack.fetch!(integration).repository_documents(row, repository: repository, path: path)
    end

    # What a delivery to a connection says was pushed, through its provider's event source, or nothing.
    def pushes(provider_key, payload, headers:)
      source = MapEvents.source_of(provider_key)
      return [] unless source.respond_to?(:branch_pushes)

      Array(source.branch_pushes(payload, headers: headers))
    rescue StandardError => error
      Rails.logger.warn({ event: "repository_documents.pushes_unread", provider: provider_key, error: error.class.name }.to_json)
      []
    end
  end
end
