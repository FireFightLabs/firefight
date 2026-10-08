module Integrations
  # A credential never reaches the model, a chat, an MCP response or the ledger, so every provider's answer passes
  # through here on its way out of the executor, remote server and native pack alike. Anything that looks like a
  # credential, in the text and in any structured value, is replaced (Chat::SecretFree.redacted). Some providers also
  # answer a read with a credential in a field of its own, such as a project's API key in its details, and the fields a
  # provider's definition names (Integrations::Provider, redacted_fields) are replaced wherever they sit in the JSON, as
  # is anything matching the credential shapes it names (redacted_patterns), each marked with its name.
  module Redactions
    REMOVED = "[REDACTED:credential]".freeze

    def self.apply(result, fields: [], patterns: {})
      content = Array(result["content"]).map do |part|
        part["text"].present? ? part.merge("text" => shaped(scrubbed_text(part["text"], fields), patterns)) : part
      end
      structured = result.key?("structuredContent") ? { "structuredContent" => shaped_value(scrubbed(result["structuredContent"], fields), patterns) } : {}
      result.merge("content" => content, **structured)
    end

    # What a provider's definition says to redact from its answers.
    def self.rules(provider_key)
      provider = Provider.for(provider_key)
      { fields: provider.redacted_fields, patterns: provider.redacted_patterns }
    end

    # The provider's own credential shapes, replaced with a marker naming each.
    def self.shaped(text, patterns) = patterns.reduce(text) { |kept, (name, pattern)| kept.gsub(pattern, "[REDACTED:#{name}]") }

    def self.shaped_value(value, patterns)
      return value if patterns.empty?

      case value
      when Hash then value.transform_values { |each| shaped_value(each, patterns) }
      when Array then value.map { |each| shaped_value(each, patterns) }
      when String then shaped(value, patterns)
      else value
      end
    end

    # JSON keeps its shape with the field's value replaced. Text that is not JSON has the field's quoted value replaced.
    def self.scrubbed_text(text, fields)
      return Chat::SecretFree.redacted(text) if fields.empty?

      scrubbed(JSON.parse(text), fields).to_json
    rescue JSON::ParserError
      named = fields.reduce(text) { |kept, field| kept.gsub(/("#{Regexp.escape(field)}"\s*:\s*)"[^"]*"/) { "#{Regexp.last_match(1)}\"#{REMOVED}\"" } }
      Chat::SecretFree.redacted(named)
    end

    def self.scrubbed(value, fields)
      case value
      when Hash then value.to_h { |key, each| [ key, fields.include?(key.to_s) && !each.nil? ? REMOVED : scrubbed(each, fields) ] }
      when Array then value.map { |each| scrubbed(each, fields) }
      when String then Chat::SecretFree.redacted(value)
      else value
      end
    end
    private_class_method :scrubbed_text, :scrubbed, :shaped, :shaped_value
  end
end
