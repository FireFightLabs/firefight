module Integrations
  # A document in a connected tool that keeps them, read through the tool's own server with Firefight's fixed reads, which
  # the handbook syncs a page from. A provider's definition names a document_reader, a RemoteReader answering
  # page(reference) with a Page, and only its switched on tools are called, each recorded under the handbook sync.
  # Nothing here names a provider.
  module Documents
    Page = Data.define(:title, :text, :url)

    module_function

    def reads?(integration) = integration.kind == Integration::KIND_MCP && Provider.for(integration.provider).document_reader.present?

    # Raises Integrations::Error with the tool's words when the document cannot be read.
    def read(integration, reference)
      row = integration.resolve_environment(nil) || integration.integration_environments.enabled.first
      raise Error, "#{integration.name} has no enabled connection to read the document through." unless row

      McpExecutor.document_of(row, reference)
    end
  end
end
