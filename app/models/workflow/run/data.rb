# Step data on its way into the run's records. Anything that looks like a credential is redacted, in and out, so a secret
# never rides from one step to the next, and a step that needs one names a connection instead. An answer too large to
# carry is kept whole as a saved result, and only a summary rides in the run's data: its short plain fields and a
# reference to the result.
module Workflow::Run::Data
  extend ActiveSupport::Concern

  # Past this many bytes of JSON a step's data is kept as a saved result.
  LARGE = 16_000
  # A plain field shorter than this rides in the summary beside the reference.
  SUMMARY_FIELD_LIMIT = 500
  KEY_SAVED_RESULT = "saved_result".freeze

  class_methods do
    def redacted(value)
      case value
      when String then Chat::SecretFree.redacted(value)
      when Hash then value.to_h { |key, inner| [ key.to_s, redacted(inner) ] }
      when Array then value.map { |inner| redacted(inner) }
      else value
      end
    end
  end

  def kept(data, step_name: nil)
    clean = self.class.redacted(data)
    json = clean.to_json
    return clean if json.bytesize <= LARGE || !clean.is_a?(Hash)

    result = saved_results.keep!(tool_name: step_name.presence || workflow.name, text: JSON.pretty_generate(clean))
    summary_of(clean).merge(KEY_SAVED_RESULT => { "id" => result.id, "handle" => result.handle, "bytes" => json.bytesize })
  end

  private

  def summary_of(data)
    data.select do |_key, value|
      value.is_a?(Numeric) || value == true || value == false || value.nil? || (value.is_a?(String) && value.size < SUMMARY_FIELD_LIMIT)
    end
  end
end
