module FirefightAi
  # Forwards a coding agent's request to the model's provider with Firefight's own key, so no key ever reaches the
  # sandbox the agent runs in. The request is pinned before it leaves: the model is the session's, the output is capped,
  # and only the agent's own tools travel, never a provider's server tools such as web search, which would reach the web
  # and be billed outside the tokens. The answer streams back as it arrives, and what the call used is read off it as it
  # goes, so a call that breaks halfway is still counted.
  class ModelProxy
    class Refused < StandardError; end

    Usage = Data.define(:input, :output, :cache_read, :cache_write) do
      def self.none = new(input: 0, output: 0, cache_read: 0, cache_write: 0)
    end

    Provider = Data.define(:base, :key, :paths, :headers, :tool_types, :output_keys)
    ANTHROPIC = "anthropic".freeze
    OPENAI = "openai".freeze
    CHAT_COMPLETIONS = "chat/completions".freeze
    READ_TIMEOUT = 600
    # Enough for any one edit a coding agent makes.
    MAX_OUTPUT_TOKENS = 32_000

    attr_reader :usage, :status

    def self.providers
      settings = FirefightAi.configuration.provider_settings
      {
        ANTHROPIC => Provider.new(base: settings[:anthropic_api_base].presence || "https://api.anthropic.com/v1", key: settings[:anthropic_api_key],
                                  paths: %w[messages], headers: %w[anthropic-version anthropic-beta], tool_types: [ nil, "custom" ],
                                  output_keys: %w[max_tokens]),
        OPENAI => Provider.new(base: settings[:openai_api_base].presence || "https://api.openai.com/v1", key: settings[:openai_api_key],
                               paths: [ CHAT_COMPLETIONS, "responses" ], headers: [], tool_types: [ "function" ],
                               output_keys: %w[max_tokens max_completion_tokens max_output_tokens])
      }
    end

    def self.supported?(provider) = providers.key?(provider.to_s)

    # The headers besides the key that the provider reads, which the caller passes through as the agent sent them.
    def self.passed_headers(provider) = providers[provider.to_s]&.headers || []

    def initialize(provider)
      @name = provider.to_s
      @provider = self.class.providers[@name] || raise(Refused, "Code fixes reach #{self.class.providers.keys.join(' or ')} models, not #{@name}.")
      raise Refused, "No #{@name} key is configured for Firefight." if @provider.key.blank?

      @usage = Usage.none
    end

    # Sends the pinned body to the path and yields :start with the status and content type, then each chunk of the
    # answer as it comes. Returns what the call used, which usage also holds when it raised halfway.
    def forward(path:, body:, model:, headers: {})
      raise Refused, "#{path} is not a path a coding agent calls." unless @provider.paths.include?(path)

      uri = URI.parse("#{@provider.base}/#{path}")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      authorize(request)
      @provider.headers.each { |name| request[name] = headers[name] if headers[name].present? }
      request.body = pinned(path, body, model).to_json
      stream(uri, request) { |*event| yield(*event) }
      @usage
    rescue Refused
      raise
    rescue StandardError => error
      raise Refused, "The model's provider could not be reached (#{error.class.name})."
    end

    private

    def stream(uri, request)
      buffer = +""
      whole = +""
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: READ_TIMEOUT) do |http|
        http.request(request) do |response|
          @status = response.code.to_i
          json = response["Content-Type"].to_s.include?("json")
          yield :start, @status, response["Content-Type"].to_s
          response.read_body do |chunk|
            yield :chunk, chunk
            json ? whole << chunk : read_usage(buffer << chunk)
          end
          json ? read_object(whole) : read_usage(buffer << "\n", finished: true)
        end
      end
    end

    def pinned(path, body, model)
      asked = JSON.parse(body.to_s)
      raise Refused, "The request must be a JSON object." unless asked.is_a?(Hash)

      Array(asked["tools"]).each do |tool|
        type = tool.is_a?(Hash) ? tool["type"] : :missing
        raise Refused, "Only the agent's own tools travel to the model, not #{type.inspect}." unless @provider.tool_types.include?(type)
      end
      asked["model"] = model
      @provider.output_keys.each { |key| asked[key] = [ asked[key].to_i, MAX_OUTPUT_TOKENS ].min if asked[key].present? }
      asked["max_tokens"] = MAX_OUTPUT_TOKENS if @name == ANTHROPIC && asked["max_tokens"].blank?
      asked["stream_options"] = (asked["stream_options"] || {}).merge("include_usage" => true) if path == CHAT_COMPLETIONS && asked["stream"]
      asked
    rescue JSON::ParserError
      raise Refused, "The request must be JSON."
    end

    def authorize(request)
      if @name == ANTHROPIC
        request["x-api-key"] = @provider.key
      else
        request["Authorization"] = "Bearer #{@provider.key}"
      end
    end

    # Each complete line of a stream can carry usage. The buffer keeps an unfinished line for the next chunk.
    def read_usage(buffer, finished: false)
      lines = buffer.split("\n", -1)
      rest = finished ? "" : lines.pop.to_s
      lines.each { |line| read_object(line.delete_prefix("data:").strip) }
      buffer.replace(rest)
    end

    def read_object(text)
      return unless text.start_with?("{")

      merge(JSON.parse(text))
    rescue JSON::ParserError
      nil
    end

    # Anthropic says the input when a message starts and the output when it ends, OpenAI says both at the end, so the
    # largest of each is kept. Anthropic counts cached tokens apart from the input, OpenAI within it, so input is always
    # the whole of it.
    def merge(object)
      found = object["usage"] || object.dig("message", "usage") || object.dig("response", "usage")
      return unless found.is_a?(Hash)

      cached = @name == ANTHROPIC ? found["cache_read_input_tokens"].to_i + found["cache_creation_input_tokens"].to_i : 0
      @usage = Usage.new(
        input: [ @usage.input, (found["input_tokens"] || found["prompt_tokens"]).to_i + cached ].max,
        output: [ @usage.output, (found["output_tokens"] || found["completion_tokens"]).to_i ].max,
        cache_read: [ @usage.cache_read, (found["cache_read_input_tokens"] || found.dig("prompt_tokens_details", "cached_tokens") ||
                                          found.dig("input_tokens_details", "cached_tokens")).to_i ].max,
        cache_write: [ @usage.cache_write, found["cache_creation_input_tokens"].to_i ].max
      )
    end
  end
end
