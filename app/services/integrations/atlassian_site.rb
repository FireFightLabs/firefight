module Integrations
  # The host of an Atlassian site, which Jira and Confluence share since Atlassian runs both on one site and one server.
  module AtlassianSite
    HOST = /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/i

    # From the site's address or a bare host name. A cloud id has no dot, so it never reads as one.
    def self.of(value)
      value = value.to_s.strip
      host = value.include?("://") ? URI.parse(value).host.to_s : value.chomp("/")
      host.downcase if host.match?(HOST)
    rescue URI::InvalidURIError
      nil
    end
  end
end
