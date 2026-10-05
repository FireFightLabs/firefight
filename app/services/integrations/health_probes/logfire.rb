module Integrations
  module HealthProbes
    # Asks Logfire for the address of the project the connection reads through project_logfire_ui_link, which only works
    # with a sign in or key Logfire accepts, and keeps it, so a query links to Logfire's live view of the same project.
    # The tool and its clean, shareable address are from Pydantic's own skill (pydantic/skills,
    # plugins/logfire/skills/logfire-ui/SKILL.md). Only an address on the region's own app is kept.
    class Logfire < RemoteReader
      UI_LINK = "project_logfire_ui_link".freeze
      ADDRESS = %r{https?://[^\s"'<>)\]]+}

      def self.address(settings) = settings&.learned.to_h["project_url"].presence

      def check!
        result = call(UI_LINK)
        return if result.nil?
        refused!(UI_LINK, result)

        found = Capabilities::Answers.text(result).scan(ADDRESS).filter_map { |each| project(each) }.first
        raise Refused, "Logfire did not answer with the address of a project in this connection's region." unless found

        { "project_url" => found }
      end

      private

      # The project's own address, without any filter, on the app of the connection's region.
      def project(address)
        uri = URI.parse(address)
        site = URI.parse(settings&.site.to_s)
        return unless uri.is_a?(URI::HTTP) && uri.userinfo.nil? && site.host.present? && uri.host == site.host
        return if uri.path.to_s.split("/").reject(&:empty?).size != 2

        "#{uri.scheme}://#{uri.host}#{uri.path.chomp('/')}"
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
