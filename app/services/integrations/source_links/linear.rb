module Integrations
  module SourceLinks
    # A Linear result about one issue, project, document or the like links to its page, the url Linear's hosted server
    # gives in the answer, as every Linear object carries in its API (the url field of Issue, Project, Document and the
    # rest in Linear's GraphQL schema) and as the issue sync reads it from save_issue (IssueTrackers::Linear). Only an
    # address on linear.app counts. A list names many, so it gets none, and neither does an answer without a url.
    class Linear
      NAME = "Linear".freeze
      PAGE = %r{\Ahttps://linear\.app/\S+\z}
      # Linear names a tool that answers one object get_ or save_, and one that answers many list_.
      ONE = /\A(get|save)_/

      def initialize(_settings); end

      def link(tool_name:, text: "", **)
        url = self.class.url_of(text) if tool_name.match?(ONE)
        Telemetry::Link.new(provider: NAME, url: url) if url
      end

      # The url of the one object the answer is, or nil.
      def self.url_of(text)
        answer = JSON.parse(text.to_s)
        url = answer["url"].to_s if answer.is_a?(Hash)
        url if url&.match?(PAGE)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
