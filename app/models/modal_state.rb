# One opaque string the platform hands back verbatim. Builders encode, the parser
# parses once, handlers read the typed Interaction#metadata.
module ModalState
  InvalidError = Class.new(StandardError)

  Result = Data.define(:incident_id, :incident_runbook_id, :temp_message_ts, :channel_id,
                       :source_message_text, :source_message_link, :prompt_handle, :test, :investigation_id, :action_item_id,
                       :memory_post_id, :memory_id) do
    def initialize(incident_id: nil, incident_runbook_id: nil, temp_message_ts: nil, channel_id: nil,
                   source_message_text: nil, source_message_link: nil, prompt_handle: nil, test: false, investigation_id: nil,
                   action_item_id: nil, memory_post_id: nil, memory_id: nil)
      super
    end
  end

  EMPTY = Result.new.freeze

  # test is encoded only when true.
  def self.encode(incident_id: nil, incident_runbook_id: nil, temp_message_ts: nil, channel_id: nil,
                  source_message_text: nil, source_message_link: nil, prompt_handle: nil, test: false, investigation_id: nil,
                  action_item_id: nil, memory_post_id: nil, memory_id: nil)
    {
      incident_id: incident_id,
      incident_runbook_id: incident_runbook_id,
      temp_message_ts: temp_message_ts,
      channel_id: channel_id,
      source_message_text: source_message_text,
      source_message_link: source_message_link,
      prompt_handle: prompt_handle,
      test: (true if test),
      investigation_id: investigation_id,
      action_item_id: action_item_id,
      memory_post_id: memory_post_id,
      memory_id: memory_id
    }.compact.to_json
  end

  def self.parse(raw)
    raise InvalidError, "modal state is blank" if raw.nil? || raw.to_s.empty?

    parsed = JSON.parse(raw)
    raise InvalidError, "modal state must be a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

    Result.new(
      incident_id: parsed["incident_id"],
      incident_runbook_id: parsed["incident_runbook_id"],
      temp_message_ts: parsed["temp_message_ts"],
      channel_id: parsed["channel_id"],
      source_message_text: parsed["source_message_text"],
      source_message_link: parsed["source_message_link"],
      prompt_handle: parsed["prompt_handle"],
      test: parsed["test"] == true,
      investigation_id: parsed["investigation_id"],
      action_item_id: parsed["action_item_id"],
      memory_post_id: parsed["memory_post_id"],
      memory_id: parsed["memory_id"]
    )
  rescue JSON::ParserError => e
    raise InvalidError, "modal state is not valid JSON: #{e.message}"
  end
end
