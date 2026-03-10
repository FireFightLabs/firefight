module Events
  class MessageHandler
    SUPPORTED_SUBTYPES = [ nil, "file_share" ].freeze

    def self.execute(platform, payload)
      event = payload["event"] || {}
      subtype = event["subtype"]
      return unless SUPPORTED_SUBTYPES.include?(subtype)

      workspace = Workspace.find_by(platform: platform, platform_id: payload["team_id"])
      return unless workspace

      channel_id = event["channel"]
      return unless channel_id

      incident = workspace.incidents.in_channel(channel_id).recent.first
      return unless incident

      message_ts = event["ts"]
      thread_ts = event["thread_ts"] || message_ts
      files = event["files"] || []

      IncidentTranscriptCache.append(
        incident: incident,
        entry: build_transcript_entry(event, incident: incident)
      )

      return if files.empty?

      member = workspace.workspace_memberships.find_by(platform_user_id: event["user"])
      permalink = fetch_permalink(workspace, channel_id, message_ts)

      files.each do |file|
        incident_event = incident.incident_events.create!(
          event_type: IncidentEvent::MESSAGE_FILE_SHARED,
          user: member,
          metadata: {
            details: {
              user_id: event["user"],
              message_ts: message_ts,
              channel_id: channel_id,
              thread_ts: thread_ts,
              permalink: permalink,
              slack_file_id: file["id"],
              file_name: file["name"],
              mime_type: file["mimetype"],
              object_key: nil
            }
          }
        )

        ArchiveIncidentFileJob.perform_later(incident_event.id, file)
      end
    rescue StandardError => e
      Rails.logger.warn({ event: "events.message.failed", error: e.message, team_id: payload["team_id"] }.to_json)
    end

    def self.build_transcript_entry(event, incident:)
      message_ts = event["ts"]
      thread_ts = event["thread_ts"] || message_ts

      {
        "message_ts" => message_ts,
        "thread_ts" => thread_ts,
        "is_thread_reply" => thread_ts != message_ts,
        "parent_ts" => (thread_ts != message_ts ? thread_ts : nil),
        "channel_id" => incident.channel_id,
        "user_id" => event["user"],
        "text" => event["text"].to_s,
        "attachments" => (event["files"] || []).map { |file| normalize_file(file) },
        "ts" => message_ts,
        "created_at" => Time.current.iso8601(6)
      }
    end
    private_class_method :build_transcript_entry

    def self.normalize_file(file)
      {
        "id" => file["id"],
        "name" => file["name"],
        "mime_type" => file["mimetype"],
        "size" => file["size"]
      }
    end
    private_class_method :normalize_file

    def self.fetch_permalink(workspace, channel_id, message_ts)
      adapter = WorkspaceAdapter.for(workspace)
      adapter.get_message_permalink(channel_id: channel_id, message_ts: message_ts)[:permalink]
    rescue AdapterError
      nil
    end
    private_class_method :fetch_permalink
  end
end
