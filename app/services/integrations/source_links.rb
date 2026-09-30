module Integrations
  # A result someone cannot check at its source is worth little, so every result that cites something links to the
  # page it came from. A native pack builds its own links. For a remote server whose results carry none, a builder here
  # works the page out from the call, and the executor adds it to what the model reads.
  module SourceLinks
    BUILDERS = { Planetscale::PROVIDER => Planetscale, Cloudflare::PROVIDER => Cloudflare }.freeze

    # The result with a line naming its page, or unchanged when there is no page to name.
    def self.attach(result, provider:, workspace:, tool_name:, arguments:)
      builder = BUILDERS[provider]
      return result unless builder

      text = Array(result["content"]).filter_map { |part| part["text"] if part["type"] == "text" }.join("\n")
      link = builder.new(workspace).link(tool_name: tool_name, arguments: arguments, text: text)
      return result unless link

      result.merge("content" => Array(result["content"]) + [ { "type" => "text", "text" => Telemetry.link_line(link) } ])
    end
  end
end
