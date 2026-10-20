module Integrations
  # The one line a person reads beside a tool, saying in plain words what it does for them. A tool's description is
  # written for the model, with what to call first and how much it returns, and stays as it is for the model. A native
  # pack's tool, or one a pack adds beside a remote server, says its summary where it is declared, and a remote server's
  # tool where the registry lists it
  # (tool_summaries in config/integration_providers.yml). A tool neither knows, such as one a team's own server
  # offers, shows the first sentence of its description, trimmed to fit.
  module ToolSummaries
    # How long a summary may be, so it reads on one line beside the tool.
    LIMIT = 90
    OMISSION = "…".freeze
    # A sentence ends at a stop followed by a capital, so "e.g. a branch" stays one sentence.
    FIRST_SENTENCE = /\A.+?[.!?](?=\s+[[:upper:]]|\z)/
    # Backticks and asterisks go wherever they are, underscores only where they open or close emphasis, so run_query keeps its own.
    MARKUP = /[`*]+|(?<![[:alnum:]])_{1,2}(?=[[:alnum:]])|(?<=[[:alnum:]])_{1,2}(?![[:alnum:]])/

    module_function

    def of(tool) = declared(tool) || first_sentence(tool.description)

    # What the tool's pack or its provider's registry entry says of it, or nil.
    def declared(tool)
      integration = tool.integration
      pack = NativePack.for(integration.provider)
      own = pack&.tool_definitions&.find { |definition| definition.name == tool.name }&.summary if integration.native? || pack&.beside_server?
      own || (IntegrationProvider.find(integration.provider)&.tool_summaries&.[](tool.name) unless integration.native?)
    end

    # The first sentence of a description, cut at a word to fit, or nil when there is none.
    def first_sentence(description)
      plain = description.to_s.gsub(/[[:cntrl:]]/, " ").gsub(MARKUP, "").squish
      return if plain.empty?

      sentence = plain[FIRST_SENTENCE] || plain
      return sentence if sentence.size <= LIMIT

      "#{sentence.truncate(LIMIT, separator: ' ', omission: '').sub(/[\s[:punct:]]+\z/, '')}#{OMISSION}"
    end
  end
end
