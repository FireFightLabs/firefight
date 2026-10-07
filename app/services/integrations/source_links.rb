module Integrations
  # A result someone cannot check at its source is worth little, so every result that cites something links to the
  # page it came from. A native pack builds its own links. For a remote server whose results carry none, the builder its
  # provider's definition names (Integrations::Provider, source_links) works the page out from the call, and the
  # executor adds it to what the model reads. An error cites nothing, so it gets no link.
  #
  # A builder is made with the connection's ConnectionSettings, for its workspace, region and what its check learned,
  # and answers link(tool_name:, arguments:, text:) with a Telemetry::Link or nil, from addresses the provider gave or
  # documents, never guessed.
  module SourceLinks
    # The result with a line naming its page, or unchanged when there is no page to name.
    def self.attach(result, settings:, tool_name:, arguments:)
      builder = Provider.for(settings.provider_key).source_links
      return result if builder.nil? || result["isError"]

      text = Array(result["content"]).filter_map { |part| part["text"] if part["type"] == "text" }.join("\n")
      link = builder.new(settings).link(tool_name: tool_name, arguments: arguments, text: text)
      return result unless link

      result.merge("content" => Array(result["content"]) + [ { "type" => "text", "text" => Telemetry.link_line(link) } ])
    end

    # The line a result names its page on, as a pack or a builder wrote it, with the provider and the address, or nil.
    # Only an https address counts, since it is shown as a link.
    CITED = %r{\AOpen this in (?<provider>[^,]+), .*give the person this link with what you found: (?<url>https://\S+)\z}
    Cited = Data.define(:line, :provider, :url)

    def self.cited_in(text)
      text.to_s.lines.map(&:strip).reverse_each do |line|
        found = line.match(CITED)
        return Cited.new(line: line, provider: found[:provider], url: found[:url]) if found
      end
      nil
    end
  end
end
