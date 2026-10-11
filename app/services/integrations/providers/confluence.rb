module Integrations
  module Providers
    Confluence = Provider.new(key: "confluence", source_links: "Integrations::SourceLinks::Confluence",
                              document_reader: "Integrations::DocumentReaders::Confluence")
  end
end
