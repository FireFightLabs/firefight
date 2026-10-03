# Searching and reading the public web, for a library's documentation, a provider's status page or an error message
# nobody here has seen. Every call goes through the gateway as whoever the agent acts for, so it is a step a finding can
# cite, and the pages come back with their addresses so whatever is used from them is cited to its source.
class Chat::Tools::Web < RubyLLM::Tool
  SEARCH = "search_web".freeze
  READ = "read_web_page".freeze
  ACTION = Ability::Action::WEB_READ

  # Not offered at all where the workspace switched web search off.
  def self.all(agent_run) = agent_run.workspace.web_search_enabled? ? [ new(agent_run, SEARCH), new(agent_run, READ) ] : []

  def initialize(agent_run, kind)
    super()
    @agent_run = agent_run
    @kind = kind
  end

  def name = @kind

  def description
    if @kind == SEARCH
      "Search the public web, such as a library's documentation for the version in use, an error message, or a " \
        "provider's status page. Each result comes with its page's text and address. Cite the address of what you use."
    else
      "Read one public web page whole, by its address, such as a documentation page a search found."
    end
  end

  def parameters_schema
    if @kind == SEARCH
      { "type" => "object", "required" => [ "query" ], "properties" => {
        "query" => { "type" => "string", "description" => "What to look for, such as \"rails 8.1 ActiveRecord::Encryption key rotation\"" },
        "domains" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Only these sites, such as [\"guides.rubyonrails.org\"] (optional)" }
      } }
    else
      { "type" => "object", "required" => [ "url" ], "properties" => { "url" => { "type" => "string", "description" => "The page's address" } } }
    end
  end

  def call(tool_call: nil, **arguments)
    asked = arguments.stringify_keys
    params = @kind == SEARCH ? asked.slice("query", "domains") : asked.slice("url")
    blocked = @agent_run.workspace.web_lookup_blocked_reason
    return blocked if blocked
    said = @agent_run.tool_call(action_key: ACTION, params: params, tool_name: name, label: label(params)) { look_up(params) }
    Chat::Tools.hand_over(@agent_run, name, said)
  rescue Integrations::WebSearch::NotConfigured, ArgumentError => error
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    error.message
  rescue Integrations::Error => error
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    FirefightAi::Evidence.frame(name, "The web could not be read: #{error.message}")
  end

  private

  def look_up(params) = @kind == SEARCH ? WebLookup.search(params["query"], domains: params["domains"]) : WebLookup.read(params["url"])

  def label(params) = @kind == SEARCH ? "Search the web for #{params['query'].to_s.truncate(80)}" : "Read #{params['url'].to_s.truncate(80)}"
end
