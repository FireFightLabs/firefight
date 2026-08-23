module Slack
  # Encodes and parses Slack modal `private_metadata`.
  #
  # Slack allows a single string up to 3KB on a view, returned verbatim on
  # submission. We use it to carry context between modal-open and modal-submit:
  # the incident the modal acts on, the runbook attachment when the modal is
  # scoped to one, and optional coordinates for a temporary "writing..."
  # message that needs cleanup after submit.
  #
  # Contract is strict. Encoded form is always a JSON object with an
  # `incident_id`. `parse` raises `InvalidError` on anything else.
  module PrivateMetadata
    InvalidError = Class.new(StandardError)

    Result = Data.define(:incident_id, :incident_runbook_id, :temp_message_ts, :channel_id) do
      def initialize(incident_id:, incident_runbook_id: nil, temp_message_ts: nil, channel_id: nil)
        super
      end
    end

    def self.encode(incident_id:, incident_runbook_id: nil, temp_message_ts: nil, channel_id: nil)
      payload = { incident_id: incident_id }
      payload[:incident_runbook_id] = incident_runbook_id if incident_runbook_id
      payload[:temp_message_ts] = temp_message_ts if temp_message_ts
      payload[:channel_id] = channel_id if channel_id
      payload.to_json
    end

    def self.parse(raw)
      raise InvalidError, "private_metadata is blank" if raw.nil? || raw.to_s.empty?

      parsed = JSON.parse(raw)
      raise InvalidError, "private_metadata must be a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

      Result.new(
        incident_id: parsed.fetch("incident_id"),
        incident_runbook_id: parsed["incident_runbook_id"],
        temp_message_ts: parsed["temp_message_ts"],
        channel_id: parsed["channel_id"]
      )
    rescue JSON::ParserError => e
      raise InvalidError, "private_metadata is not valid JSON: #{e.message}"
    rescue KeyError => e
      raise InvalidError, "private_metadata missing key: #{e.message}"
    end
  end
end
