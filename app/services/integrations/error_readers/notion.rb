module Integrations
  module ErrorReaders
    # Notion's server answers an API error with the API's error, whose code for a page, database or block that is not
    # there or not shared is object_not_found with status 404 (developers.notion.com/reference/status-codes). Seen from
    # the hosted server as {"name":"APIResponseError","code":"object_not_found","status":404,...}.
    module Notion
      NOT_FOUND = /"code"\s*:\s*"object_not_found"/

      def self.not_found?(said) = said.match?(NOT_FOUND)
    end
  end
end
