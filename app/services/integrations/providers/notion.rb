module Integrations
  module Providers
    Notion = Provider.new(key: "notion", error_reader: "Integrations::ErrorReaders::Notion", document_reader: "Integrations::DocumentReaders::Notion")
  end
end
