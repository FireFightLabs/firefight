module Mcp
  module Tools
    # An outside system's public status page, read now (Integrations::StatusPages), for when errors point outward, such
    # as timeouts calling a payment provider. Reading a public page reaches nothing of the workspace's, so it is a web
    # read, open to every caller and switched off with the workspace's web search.
    class CheckStatusPage < Base
      tool_name CHECK_STATUS_PAGE
      authorize_as Ability::Action::RESOURCE_WEB
      description "Read an outside provider's public status page now: whether it reports an outage or degraded service, its " \
                  "open incidents with their latest update, and what is not fully working, with the page's address. Use it " \
                  "whenever errors point outside, such as timeouts, refused connections or 5xx answers from a third party's " \
                  "host, before blaming the team's own code. Name the provider, or give the host the errors name and the " \
                  "provider is found from it. Docs: #{Docs::WHAT_CHANGED}"
      annotations(**READ_ONLY)
      input_schema(
        properties: {
          provider: { type: "string", enum: Upstream.all.select(&:status_page).map(&:name),
                      description: "The provider whose status page to read (optional when host is given)" },
          host: { type: "string", description: "A host the errors name, such as api.stripe.com, to find the provider by (optional when provider is given)" }
        },
        required: []
      )

      def self.perform(workspace:, args:)
        entry = Upstream.named(args[:provider]) || Upstream.for_host(args[:host])
        return Mcp::ToolDispatcher.error_response(unknown(args)) unless entry&.status_page

        blocked = workspace.web_lookup_blocked_reason
        return Mcp::ToolDispatcher.error_response("#{blocked} #{entry.name}'s status page is #{entry.status_page.url}, which a person can open.") if blocked

        ::MCP::Tool::Response.new([ { type: "text", text: Integrations::StatusPages.words(Integrations::StatusPages.read(entry)) } ])
      rescue Integrations::Error, ArgumentError => error
        Mcp::ToolDispatcher.error_response("#{entry.name}'s status page could not be read: #{error.message} It is at #{entry.status_page.url}.")
      end

      def self.unknown(args)
        return "Name a provider, or a host the errors name." if args[:provider].blank? && args[:host].blank?

        asked = args[:provider].presence || args[:host]
        "Firefight knows no status page for #{asked}. Search the web for its status page, or name one of the providers this tool lists."
      end
      private_class_method :unknown
    end
  end
end
