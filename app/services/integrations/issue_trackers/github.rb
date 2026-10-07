module Integrations
  module IssueTrackers
    # GitHub's pack opens an issue with create_issue and closes one with close_issue, each answering with the issue's page
    # (its html_url, https://github.com/<owner>/<repo>/issues/<number>) on the line Telemetry.link_line writes. That page
    # is read back from the answer, so nothing more is asked of GitHub. GitHub issues report only what Halon did. Keeping
    # items in step with them is not offered, so there is no CREATE_TOOL.
    class Github < RemoteReader
      CREATE = "create_issue".freeze
      CLOSE = "close_issue".freeze
      OPENS = [ CREATE ].freeze
      PAGE = %r{\Ahttps://github\.com/(?<repo>[\w.\-]+/[\w.\-]+)/issues/(?<number>\d+)\z}

      def report(tool_name:, arguments:, result:)
        change = { CREATE => Issues::OPENED, CLOSE => Issues::CLOSED }[tool_name]
        return unless change

        said = Array(result["content"]).filter_map { |part| part["text"] }.join("\n")
        found = SourceLinks.cited_in(said)&.url.to_s.match(PAGE)
        return unless found

        title = arguments["title"].to_s.strip.presence if change == Issues::OPENED
        Issues::Report.new(change: change, key: "#{found[:repo]}##{found[:number]}", title: title, url: found.to_s)
      end
    end
  end
end
