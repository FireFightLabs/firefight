module Integrations
  module Providers
    Notion = Provider.new(key: "notion", error_reader: "Integrations::ErrorReaders::Notion")
  end
end
