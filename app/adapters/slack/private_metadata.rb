module Slack
  # Encodes and parses Slack modal `private_metadata`.
  #
  # Slack allows a single string up to 3KB on a view, returned verbatim on
  # submission. We use it to carry context between modal-open and modal-submit:
  # the incident the modal acts on, the runbook attachment when the modal is
  # scoped to one, and optional coordinates for a temporary "writing..."
  # message that needs cleanup after submit.
  #
  # One encoder and one decoder. Every modal builder calls `encode`, the
  # interaction parser calls `parse` once at the boundary, and handlers read
  # the typed `Interaction#metadata`. A modal that carries no incident (the
  # home modal) leaves `incident_id` nil. `parse` raises `InvalidError` on
  # anything that is not a JSON object.
  module PrivateMetadata
    InvalidError = Class.new(StandardError)

    Result = Data.define(:incident_id, :incident_runbook_id, :temp_message_ts, :channel_id,
                         :source_message_text, :source_message_link) do
      def initialize(incident_id: nil, incident_runbook_id: nil, temp_message_ts: nil, channel_id: nil,
                     source_message_text: nil, source_message_link: nil)
        super
      end
    end

    EMPTY = Result.new.freeze

    def self.encode(incident_id: nil, incident_runbook_id: nil, temp_message_ts: nil, channel_id: nil,
                    source_message_text: nil, source_message_link: nil)
      {
        incident_id: incident_id,
        incident_runbook_id: incident_runbook_id,
        temp_message_ts: temp_message_ts,
        channel_id: channel_id,
        source_message_text: source_message_text,
        source_message_link: source_message_link
      }.compact.to_json
    end

    def self.parse(raw)
      raise InvalidError, "private_metadata is blank" if raw.nil? || raw.to_s.empty?

      parsed = JSON.parse(raw)
      raise InvalidError, "private_metadata must be a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

      Result.new(
        incident_id: parsed["incident_id"],
        incident_runbook_id: parsed["incident_runbook_id"],
        temp_message_ts: parsed["temp_message_ts"],
        channel_id: parsed["channel_id"],
        source_message_text: parsed["source_message_text"],
        source_message_link: parsed["source_message_link"]
      )
    rescue JSON::ParserError => e
      raise InvalidError, "private_metadata is not valid JSON: #{e.message}"
    end
  end
end
