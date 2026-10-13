module FirefightAi
  # Forwards a coding agent's request to the model's provider with the payer's key, so no key ever reaches the sandbox
  # the agent runs in. The key and address come from the configuration the payer runs with: a workspace's own account's
  # context, or the deployment's own. The request is pinned before it leaves: the model is the session's, the output is capped,
  # and only the agent's own tools travel, never a provider's server tools such as web search, which would reach the web
  # and be billed outside the tokens. The answer streams back as it arrives, and what the call used is read off it as it
  # goes, so a call that breaks halfway is still counted, with the tools it called (Calls). Given a Clearing, the oldest
  # tool results of a long session are cleared in batches before the call leaves (History).
  class ModelProxy
    class Refused < StandardError; end

    # cache_write_by_ttl splits cache_write by how long each write lasts, as Anthropic reports it, such as { "1h" => 2048 },
    # since an hour's write costs more than five minutes'.
    Usage = Data.define(:input, :output, :cache_read, :cache_write, :cache_write_by_ttl) do
      def initialize(input:, output:, cache_read:, cache_write:, cache_write_by_ttl: {}) = super

      def self.none = new(input: 0, output: 0, cache_read: 0, cache_write: 0)
    end

    # Anthropic's names for the cache writes of each lifetime, inside usage's cache_creation.
    CACHE_CREATION_BY_TTL = /\Aephemeral_(.+)_input_tokens\z/

    # wires holds each path the provider takes. key_header is the header its key goes in, a bearer token when nil.
    Provider = Data.define(:base, :key, :wires, :dropped_keys, :key_header) do
      def paths = wires.keys
    end
    # A request format: the headers the provider reads in it besides the key, the types the agent's own tools come as
    # and the keys that cap the output.
    Wire = Data.define(:headers, :tool_types, :output_keys)

    ANTHROPIC = "anthropic".freeze
    OPENAI = "openai".freeze
    OPENROUTER = "openrouter".freeze
    SUPPORTED = [ ANTHROPIC, OPENAI, OPENROUTER ].freeze
    CHAT_COMPLETIONS = History::CHAT_COMPLETIONS
    MESSAGES = History::MESSAGES
    RESPONSES = History::RESPONSES
    BETA_HEADER = "anthropic-beta".freeze
    # Anthropic's own format, which OpenRouter also takes for Anthropic's models, counts cached tokens apart from the
    # input, and is the one where the provider clears old tool results itself.
    ANTHROPIC_FORMAT = Wire.new(headers: [ "anthropic-version", BETA_HEADER ], tool_types: [ nil, "custom" ], output_keys: %w[max_tokens])
    CHAT_FORMAT = Wire.new(headers: [], tool_types: [ "function" ], output_keys: %w[max_tokens max_completion_tokens])
    RESPONSES_FORMAT = CHAT_FORMAT.with(output_keys: %w[max_tokens max_completion_tokens max_output_tokens])
    # How OpenRouter names Anthropic's models, by their maker.
    OPENROUTER_ANTHROPIC = "anthropic/".freeze
    READ_TIMEOUT = 600
    # Enough for any one edit a coding agent makes.
    MAX_OUTPUT_TOKENS = 32_000

    # What a coding agent's history is cleared with: how many results each conversation already cleared, by its key,
    # whether the provider may still be asked to clear them itself, and the tools whose results are never cleared.
    Clearing = Data.define(:through, :server, :kept_tools)

    # What clearing did on one call: the conversation's key, how many of its oldest results are cleared now, whether the
    # provider was asked to clear them, and whether it refused the request for being asked, so it is not asked again.
    Trim = Data.define(:conversation, :count, :by_provider, :provider_refused)

    attr_reader :usage, :status, :trim

    # The tools the answer called and what the provider cleared (Calls).
    attr_reader :calls

    # The provider's answer to a refused call, kept so the refusal can be read, such as for credit.
    attr_reader :refusal

    # The provider's own id for the call, from its answer's headers (RequestId).
    attr_reader :request_id

    def self.providers(config = RubyLLM.config)
      {
        # Anthropic calls remote MCP servers named at the top of the body and keeps code execution state in a container,
        # and neither sits under tools, where the tool check looks, so both are dropped.
        ANTHROPIC => Provider.new(base: config.anthropic_api_base.presence || "https://api.anthropic.com/v1", key: config.anthropic_api_key,
                                  wires: { MESSAGES => ANTHROPIC_FORMAT }, dropped_keys: %w[mcp_servers container], key_header: "x-api-key"),
        OPENAI => Provider.new(base: config.openai_api_base.presence || "https://api.openai.com/v1", key: config.openai_api_key,
                               wires: { CHAT_COMPLETIONS => CHAT_FORMAT, RESPONSES => RESPONSES_FORMAT }, dropped_keys: [], key_header: nil),
        # OpenRouter speaks OpenAI's chat format, and Anthropic's own for Anthropic's models. Its fallback models, routes
        # and plugins such as web search would reach another model or the web, so they never travel, and neither do the
        # remote MCP servers and container Anthropic's format can name.
        OPENROUTER => Provider.new(base: config.openrouter_api_base.presence || "https://openrouter.ai/api/v1", key: config.openrouter_api_key,
                                   wires: { CHAT_COMPLETIONS => CHAT_FORMAT, MESSAGES => ANTHROPIC_FORMAT },
                                   dropped_keys: %w[models route plugins mcp_servers container], key_header: nil)
      }
    end

    def self.supported?(provider) = SUPPORTED.include?(provider.to_s)

    # The headers besides the key that the provider reads, which the caller passes through as the agent sent them.
    def self.passed_headers(provider) = providers[provider.to_s]&.wires&.values&.flat_map(&:headers)&.uniq || []

    # Whether a coding agent reaches the model in Anthropic's own format, where the provider clears old tool results
    # itself. Anthropic always does, and OpenRouter does for Anthropic's models, which it serves in that format too.
    def self.anthropic_format?(provider, model)
      provider.to_s == ANTHROPIC || (provider.to_s == OPENROUTER && model.to_s.start_with?(OPENROUTER_ANTHROPIC))
    end

    # config is the RubyLLM configuration the payer runs with, the deployment's own when nil. connect_to, when given,
    # takes the provider's host and answers the address to connect to, raising when it may not be reached, so an address
    # a workspace named is checked again on every call.
    def initialize(provider, config: nil, connect_to: nil)
      @name = provider.to_s
      @connect_to = connect_to
      @provider = self.class.providers(config || RubyLLM.config)[@name] ||
                  raise(Refused, "Code fixes reach #{SUPPORTED.to_sentence(last_word_connector: ' or ')} models, not #{@name}.")
      raise Refused, "No #{@name} key is configured for this code change." if @provider.key.blank?

      @usage = Usage.none
      @calls = Calls.new
    end

    # Sends the pinned body to the path and yields :start with the status and content type, then each chunk of the
    # answer as it comes. Returns what the call used, which usage also holds when it raised halfway. With clearing, the
    # oldest tool results are cleared first, and a provider that refuses the request for being asked to clear them is
    # asked once more without it, before anything was yielded.
    def forward(path:, body:, model:, headers: {}, clearing: nil, &)
      @path = path
      @wire = @provider.wires[path] || raise(Refused, "#{path} is not a path a coding agent calls.")
      asked = pinned(body, model)
      whole = asked.deep_dup
      by_provider = clear!(asked, clearing)
      return @usage if send_request(asked, headers, by_provider, &)

      @trim = @trim.with(by_provider: false, provider_refused: true)
      @calls = Calls.new
      send_request(whole, headers, false, &)
      @usage
    rescue Refused
      raise
    rescue StandardError => error
      raise Refused, "The model's provider could not be reached (#{error.class.name})."
    end

    private

    def clear!(asked, clearing)
      return false unless clearing && History.reads?(@path)

      history = History.new(asked, wire: @path, kept_tools: clearing.kept_tools)
      count = history.clear_through(clearing.through.to_h[history.conversation])
      by_provider = history.apply!(count, server: clearing.server && @wire == ANTHROPIC_FORMAT)
      @trim = Trim.new(conversation: history.conversation, count: count, by_provider: by_provider, provider_refused: false)
      by_provider
    end

    # False only when the provider refused the request for the clearing it was asked for, and then nothing was yielded.
    def send_request(asked, headers, clearing, &)
      uri = URI.parse("#{@provider.base}/#{@path}")
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      authorize(request)
      @wire.headers.each { |name| request[name] = headers[name] if headers[name].present? }
      request[BETA_HEADER] = [ request[BETA_HEADER].presence, History::SERVER_BETA ].compact.join(",") if clearing
      request.body = asked.to_json
      stream(uri, request, clearing, &)
    end

    def stream(uri, request, clearing)
      buffer = +""
      whole = +""
      options = { use_ssl: uri.scheme == "https", read_timeout: READ_TIMEOUT, ipaddr: @connect_to&.call(uri.host) }.compact
      Net::HTTP.start(uri.host, uri.port, **options) do |http|
        http.request(request) do |response|
          @status = response.code.to_i
          @request_id = RequestId.in_headers(RequestId::HEADERS.to_h { |name| [ name, response[name] ] })
          type = response["Content-Type"].to_s
          json = type.include?("json")
          if clearing && @status == 400
            response.read_body { |chunk| whole << chunk }
            return false if refused_clearing?(whole)

            yield :start, @status, type
            yield :chunk, whole
          else
            yield :start, @status, type
            response.read_body do |chunk|
              yield :chunk, chunk
              json ? whole << chunk : read_usage(buffer << chunk)
            end
          end
          json ? read_object(whole) : read_usage(buffer << "\n", finished: true)
          @refusal = Credit.new(status: @status, body: whole) if json && @status >= 400
        end
      end
      true
    end

    def refused_clearing?(body) = body.include?("context_management") || body.include?(History::SERVER_BETA)

    def pinned(body, model)
      asked = JSON.parse(body.to_s)
      raise Refused, "The request must be a JSON object." unless asked.is_a?(Hash)

      Array(asked["tools"]).each do |tool|
        type = tool.is_a?(Hash) ? tool["type"] : :missing
        raise Refused, "Only the agent's own tools travel to the model, not #{type.inspect}." unless @wire.tool_types.include?(type)
      end
      @provider.dropped_keys.each { |key| asked.delete(key) }
      asked["model"] = model
      @wire.output_keys.each { |key| asked[key] = [ asked[key].to_i, MAX_OUTPUT_TOKENS ].min if asked[key].present? }
      asked["max_tokens"] = MAX_OUTPUT_TOKENS if @wire == ANTHROPIC_FORMAT && asked["max_tokens"].blank?
      asked["stream_options"] = (asked["stream_options"] || {}).merge("include_usage" => true) if @path == CHAT_COMPLETIONS && asked["stream"]
      asked
    rescue JSON::ParserError
      raise Refused, "The request must be JSON."
    end

    def authorize(request)
      if @provider.key_header
        request[@provider.key_header] = @provider.key
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

      object = JSON.parse(text)
      @calls.read(object)
      merge(object)
    rescue JSON::ParserError
      nil
    end

    # Anthropic's format says the input when a message starts and the output when it ends, OpenAI says both at the end,
    # so the largest of each is kept. Anthropic's format counts cached tokens apart from the input, OpenAI within it, so
    # input is always the whole of it.
    def merge(object)
      found = object["usage"] || object.dig("message", "usage") || object.dig("response", "usage")
      return unless found.is_a?(Hash)

      cached = @wire == ANTHROPIC_FORMAT ? found["cache_read_input_tokens"].to_i + found["cache_creation_input_tokens"].to_i : 0
      @usage = Usage.new(
        input: [ @usage.input, (found["input_tokens"] || found["prompt_tokens"]).to_i + cached ].max,
        output: [ @usage.output, (found["output_tokens"] || found["completion_tokens"]).to_i ].max,
        cache_read: [ @usage.cache_read, (found["cache_read_input_tokens"] || found.dig("prompt_tokens_details", "cached_tokens") ||
                                          found.dig("input_tokens_details", "cached_tokens")).to_i ].max,
        cache_write: [ @usage.cache_write, found["cache_creation_input_tokens"].to_i ].max,
        cache_write_by_ttl: @usage.cache_write_by_ttl.merge(cache_written_by_ttl(found)) { |_ttl, seen, now| [ seen, now ].max }
      )
    end

    def cache_written_by_ttl(found)
      created = found["cache_creation"]
      return {} unless created.is_a?(Hash)

      created.filter_map { |key, count| [ key[CACHE_CREATION_BY_TTL, 1], count.to_i ] if key.match?(CACHE_CREATION_BY_TTL) && count.to_i.positive? }.to_h
    end
  end
end
