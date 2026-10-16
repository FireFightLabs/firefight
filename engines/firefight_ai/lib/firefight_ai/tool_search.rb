module FirefightAi
  # Whether the provider behind a choice searches tools itself, as Anthropic's tool search and OpenAI's Responses do, so
  # a tool handed over deferred stays out of the model's context until the model searches for it. Anywhere else RubyLLM
  # sends a deferred tool as an ordinary one, so a long list would land in the context whole.
  #
  # RubyLLM says it only in the request it would send, where a chat holding one deferred tool gains the provider's own
  # search tool. That request is rendered here, never sent, and the answer is kept per provider and model.
  module ToolSearch
    class Probe < RubyLLM::Tool
      description "Stands in for a deferred tool while the request is rendered."

      def name = "firefight_tool_search_probe"

      def execute = nil
    end

    SEARCH_TYPE = /\Atool_search/

    @known = Concurrent::Map.new

    def self.native?(choice)
      key = [ choice.provider_name, choice.model ]
      known = @known[key]
      return known unless known.nil?

      found = probe(choice)
      found.nil? ? false : @known.compute_if_absent(key) { found }
    end

    # nil when no request can be rendered for the choice, such as a provider with no key here, which is not kept, since
    # the call itself would be refused the same way.
    def self.probe(choice)
      chat = FirefightAi.chat(choice).with_tools(Probe.new, defer: true)
      chat.add_message(role: :user, content: ".")
      tools = chat.render.then { |payload| payload[:tools] || payload["tools"] }
      Array(tools).any? { |tool| tool.is_a?(Hash) && (tool[:type] || tool["type"]).to_s.match?(SEARCH_TYPE) }
    rescue RubyLLM::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError, ArgumentError, NotImplementedError
      nil
    end

    def self.forget! = @known.clear
  end
end
