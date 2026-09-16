# How the agent discovers what it can do. Matches are offered to the chat, so the next turn can
# call them for real, and a tool the agent may not use is still named rather than hidden.
class Chat::Tools::Find < RubyLLM::Tool
  MATCH_LIMIT = 8

  description "Find the tools available for what you need to do next, such as 'recent deploys', " \
              "'incidents mentioning checkout' or 'runbooks'. Tools you are allowed to use become " \
              "callable straight after this. Call it before saying you cannot check something."
  parameter :query, description: "What you are trying to find out, in a few words"

  def self.tool_name = "find_tools"

  def initialize(agent_run, offer:)
    super()
    @agent_run = agent_run
    @offer = offer
  end

  def execute(query:)
    matches = Chat::Tools.catalog(@agent_run).select { |entry| entry.matches?(query) }.first(MATCH_LIMIT)
    return "Nothing matches #{query.inspect}. Say what you could not check rather than guessing." if matches.empty?

    @offer.call(matches.filter_map(&:tool))
    matches.map { |entry| line_for(entry) }.join("\n")
  end

  private

  def line_for(entry)
    case entry.state
    when Chat::Tools::STATE_READY then "#{entry.name}: #{entry.description} (ready to call)"
    when Chat::Tools::STATE_NOT_GRANTED then "#{entry.name}: #{entry.description} (exists, but this workspace has not granted it to you)"
    else "#{entry.name}: not connected in this workspace"
    end
  end
end
