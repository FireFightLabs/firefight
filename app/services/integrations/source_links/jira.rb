module Integrations
  module SourceLinks
    # A Jira result about one issue links to that issue's page, https://<site>/browse/<KEY>, the address Atlassian's own
    # agent skills give for an issue (atlassian/atlassian-mcp-server, skills/triage-issue). The site comes from the
    # call's cloudId when it names the site by its address, which Atlassian's server accepts in place of the id. A
    # cloudId given as an id, or an issue given by its number rather than its key, gets no link, since the site or the
    # key would have to be looked up. A search gets none either, since Atlassian documents no address for one.
    class Jira
      NAME = "Jira".freeze
      CLOUD_ID = "cloudId".freeze
      ISSUE = "issueIdOrKey".freeze
      # Tools are named as discovery stores them, lowercased from Atlassian's own names.
      CREATE_ISSUE = "createjiraissue".freeze
      ISSUE_KEY = /\A[A-Z][A-Z0-9_]+-\d+\z/
      # The key Jira gives a new issue, as its answer names it.
      CREATED_KEY = /"key"\s*:\s*"([A-Z][A-Z0-9_]+-\d+)"/
      HOST = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/i

      def initialize(_settings); end

      def link(tool_name:, arguments:, text: "")
        asked = arguments.to_h.stringify_keys
        site = site_of(asked[CLOUD_ID])
        key = tool_name == CREATE_ISSUE ? text.to_s[CREATED_KEY, 1] : asked[ISSUE].to_s.strip
        return unless site && key.to_s.match?(ISSUE_KEY)

        Telemetry::Link.new(provider: NAME, url: "https://#{site}/browse/#{key}")
      end

      private

      # The site's host, from its address or a bare host name. An id has no dot, so it never reads as one.
      def site_of(cloud_id)
        value = cloud_id.to_s.strip
        host = value.include?("://") ? URI.parse(value).host.to_s : value.chomp("/")
        host.downcase if host.match?(HOST)
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
