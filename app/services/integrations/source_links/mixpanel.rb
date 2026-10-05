module Integrations
  module SourceLinks
    # Mixpanel's pages live under its project addresses, <site>/project/<id>/view/<workspace>/app/..., on the site of the
    # connection's region (docs.mixpanel.com, Mixpanel's MCP and report pages). A call alone does not say which workspace
    # a page is in, so no address is pieced together. When an answer names exactly one page on that site, such as a
    # report, board or flag it read, that page becomes the link line. Several, or none, gets no link.
    class Mixpanel
      NAME = "Mixpanel".freeze

      def initialize(settings)
        site = settings.site
        @page = %r{#{Regexp.escape(site.chomp('/'))}/project/\d+[^\s"'<>()\[\]`]*} if site
      end

      def link(tool_name:, arguments:, text: "")
        return unless @page

        pages = text.to_s.scan(@page).map { |url| url.sub(/[.,;:]+\z/, "") }.uniq
        Telemetry::Link.new(provider: NAME, url: pages.first) if pages.one?
      end
    end
  end
end
