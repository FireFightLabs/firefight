module Integrations
  module IssueTrackers
    # Linear's save_issue opens an issue when it is called without an id and changes one when it is given one. It
    # answers the issue as JSON with its key (id), title, url and statusType, one of Linear's workflow state types
    # (backlog, unstarted, started, completed, canceled), as Linear's hosted server answers it. A change that leaves the
    # issue completed or canceled closes it.
    class Linear < RemoteReader
      SAVE_ISSUE = "save_issue".freeze
      CLOSED_TYPES = %w[completed canceled].freeze
      OPENS = [ SAVE_ISSUE ].freeze

      def report(tool_name:, arguments:, result:)
        return unless tool_name == SAVE_ISSUE

        issue = Capabilities::Answers.data(result)
        return unless issue.is_a?(Hash) && issue["url"].to_s.match?(%r{\Ahttps://\S+\z})

        change = if arguments["id"].blank? then Issues::OPENED
        elsif CLOSED_TYPES.include?(issue["statusType"]) then Issues::CLOSED
        end
        return unless change

        Issues::Report.new(change: change, key: issue["id"].presence, title: issue["title"].to_s.strip.presence, url: issue["url"])
      end
    end
  end
end
