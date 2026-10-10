# Searches the workspace's handbook pages, which a chat or run holds whole when they are short and reads through here
# when they are long. Answers the best few sections in full, each with its page and the page's link, so Halon can cite
# the page it follows, and the step in the chat or run shows which pages answered. Each search is a read through the
# gateway as handbook.read, so a run searches only while the investigator holds it.
class Chat::Tools::SearchHandbook < RubyLLM::Tool
  def self.tool_name = "search_handbook"

  def initialize(agent_run)
    super()
    @agent_run = agent_run
  end

  def name = self.class.tool_name

  def description
    "Search this workspace's handbook, how the workspace works as its people wrote it, such as how a release runs, who " \
      "owns a service or when changes are frozen. Use it for the pages the start of the chat names as too long to give " \
      "there, and whenever the handbook may say how to do what you are about to do. Answers the best few sections whole, " \
      "each with its page and link. Follow what they say, and cite the page by its link."
  end

  def parameters_schema
    { "type" => "object", "required" => [ "query" ], "properties" => {
      "query" => { "type" => "string", "description" => "What to find, such as \"release steps\" or \"who owns checkout\"" }
    } }
  end

  def call(tool_call: nil, **arguments)
    query = arguments.stringify_keys["query"].to_s.strip
    return refused(tool_call, "Say what to look for in query.") if query.empty?

    @agent_run.handbook_read(params: { "query" => query }, tool_name: name) { answer(query) }
  rescue AbilityGateway::Denied => denied
    refused(tool_call, @agent_run.refusal(denied.action_key))
  end

  private

  def workspace = @agent_run.workspace

  def answer(query)
    search = Chat::HandbookChunk::Search.new(query, workspace: workspace, model: FirefightAi.embedding_model, meaning: meaning(query))
    hits = search.hits
    return "Nothing in the handbook matched #{query.inspect}." if hits.empty?

    hits.each_with_index.map do |hit, index|
      chunk = hit.chunk
      heading = chunk.heading_path.split(ProviderDocPage::Chunking::PATH_JOIN).drop(1).last
      "#{index + 1}. #{chunk.heading_path}\n   Page \"#{chunk.page.title}\" (#{chunk.page.url(heading: heading)})\n\n#{chunk.text}"
    end.join("\n\n")
  end

  def refused(tool_call, words)
    Chat::Tools.mark_failed(@agent_run, tool_call&.id)
    words
  end

  # The query's vector, or nil when no model can embed it, which leaves words alone.
  def meaning(query)
    lambda do
      SearchEmbeddingService.new(workspace).query_vector(query)
    rescue FirefightAi::Error
      nil
    end
  end
end
