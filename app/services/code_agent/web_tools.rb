# search_web and read_web_page for a coding agent, the same lookups Halon makes, each one in the ledger under the
# session's workspace, counted against the session and the workspace's day, and framed as evidence the agent reads,
# never instructions it follows. None at all where the workspace switched web search off.
module CodeAgent::WebTools
  def self.for(session)
    return [] unless session.workspace.web_search_enabled?

    [
      ::MCP::Tool.define(
        name: Chat::Tools::Web::SEARCH,
        description: "Search the public web, such as a library's documentation for the version the repository installs. " \
                     "Each result comes with its page's text and address.",
        input_schema: { type: "object", required: [ "query" ], properties: {
          query: { type: "string" }, domains: { type: "array", items: { type: "string" } }
        } },
        annotations: { read_only_hint: true }
      ) do |query:, domains: [], **|
        CodeAgent::WebTools.answer(session, Chat::Tools::Web::SEARCH, { "query" => query, "domains" => domains }) { WebLookup.search(query, domains: domains) }
      end,
      ::MCP::Tool.define(
        name: Chat::Tools::Web::READ,
        description: "Read one public web page whole, by its address.",
        input_schema: { type: "object", required: [ "url" ], properties: { url: { type: "string" } } },
        annotations: { read_only_hint: true }
      ) { |url:, **| CodeAgent::WebTools.answer(session, Chat::Tools::Web::READ, { "url" => url }) { WebLookup.read(url) } }
    ]
  end

  def self.answer(session, name, params, &)
    blocked = session.workspace.web_lookup_blocked_reason || (CodeAgentSession::TOO_MANY_LOOKUPS unless session.count_web_lookup!)
    return refusal(blocked) if blocked

    ::MCP::Tool::Response.new([ { type: "text", text: FirefightAi::Evidence.frame(name, session.look_up_web!(params, &)) } ])
  rescue Integrations::Error, ArgumentError => error
    refusal(error.message)
  end

  def self.refusal(text) = ::MCP::Tool::Response.new([ { type: "text", text: text } ], error: true)
end
