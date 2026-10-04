module Integrations
  # Some providers answer a read with a credential in it, such as a project's own API key in a project's details. A
  # credential never reaches the model, a chat or an MCP response, so the fields a provider's definition names
  # (Integrations::Provider, redacted_fields) are replaced in its answer before anything reads it, wherever they sit in
  # the JSON.
  module Redactions
    REMOVED = "[REDACTED:credential]".freeze

    def self.apply(result, fields:)
      return result if fields.empty?

      content = Array(result["content"]).map { |part| part["text"].present? ? part.merge("text" => scrubbed_text(part["text"], fields)) : part }
      structured = result.key?("structuredContent") ? { "structuredContent" => scrubbed(result["structuredContent"], fields) } : {}
      result.merge("content" => content, **structured)
    end

    # JSON keeps its shape with the field's value replaced. Text that is not JSON has the field's quoted value replaced.
    def self.scrubbed_text(text, fields)
      scrubbed(JSON.parse(text), fields).to_json
    rescue JSON::ParserError
      fields.reduce(text) { |kept, field| kept.gsub(/("#{Regexp.escape(field)}"\s*:\s*)"[^"]*"/) { "#{Regexp.last_match(1)}\"#{REMOVED}\"" } }
    end

    def self.scrubbed(value, fields)
      case value
      when Hash then value.to_h { |key, each| [ key, fields.include?(key.to_s) && !each.nil? ? REMOVED : scrubbed(each, fields) ] }
      when Array then value.map { |each| scrubbed(each, fields) }
      else value
      end
    end
    private_class_method :scrubbed_text, :scrubbed
  end
end
