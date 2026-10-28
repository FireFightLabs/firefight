module FirefightAi
  module Providers
    # What the Chat Completions APIs of Z.AI, MiniMax and Alibaba Cloud Model Studio share and OpenAI's does not. A system
    # message is called system. A reply's reasoning goes back on the next turn as reasoning_content, which a model that
    # reasons between tool calls needs to carry on. Each caches by itself, so no prompt cache fields are sent. Files other
    # than images are not taken. None enforces a JSON Schema everywhere, so a schema is asked for in words, with JSON
    # mode where the provider has it.
    module Dialect
      SCHEMA_WORDS = "Answer with only one JSON object that matches this JSON Schema, with no other text before or after it:\n%s".freeze
      FENCED = /\A\s*```(?:json)?\s*\n?(.*?)\n?\s*```\s*\z/m
      JSON_MODE = { type: "json_object" }.freeze

      def format_role(role) = role.to_s

      def openai_prompt_caching? = false

      def render_payload(messages, tools:, temperature:, model:, stream: false, max_output_tokens: nil, schema: nil, thinking: nil,
                         citations: false, caching: nil, tool_prefs: nil)
        payload = super(messages, tools:, temperature:, model:, stream:, max_output_tokens:, schema: nil, thinking:, citations:, caching:, tool_prefs:)
        @schema_asked = schema.present?
        ask_for_schema(payload, schema) if schema
        payload
      end

      # A model asked for JSON in words sometimes fences it, which the caller would fail to read.
      def parse_completion_body(data, raw:)
        content = data.dig("choices", 0, "message", "content")
        data["choices"][0]["message"]["content"] = content[FENCED, 1] if @schema_asked && content.is_a?(String) && content.match?(FENCED)
        super
      end

      def format_thinking(msg)
        text = msg.thinking&.text
        msg.role == :assistant && text.present? ? { reasoning_content: text } : {}
      end

      def supported_attachment?(attachment)
        RubyLLM::Protocols::ChatCompletions::Media.supported_attachment?(attachment, document_attachments: :none, audio_attachments: false)
      end

      def format_content(content, attachments = [])
        RubyLLM::Protocols::ChatCompletions::Media.format_content(content, attachments, document_attachments: :none, audio_attachments: false)
      end

      # Whether the provider has a JSON mode, which makes the reply one JSON object without holding it to a schema.
      def json_mode? = true

      private

      # After the instructions, so what they say first stays the same from call to call and the provider's cache holds.
      def ask_for_schema(payload, schema)
        words = { role: "system", content: format(SCHEMA_WORDS, JSON.generate(schema[:schema])) }
        at = payload[:messages].index { |message| message[:role] != "system" } || payload[:messages].size
        payload[:messages].insert(at, words)
        payload[:response_format] = JSON_MODE if json_mode?
      end
    end
  end
end
