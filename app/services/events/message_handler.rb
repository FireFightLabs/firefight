module Events
  class MessageHandler
    SUPPORTED_SUBTYPES = [
      nil,
      Identifiers::MESSAGE_SUBTYPE_FILE_SHARE,
      Identifiers::MESSAGE_SUBTYPE_MESSAGE_CHANGED,
      Identifiers::MESSAGE_SUBTYPE_MESSAGE_DELETED
    ].freeze

    def self.execute(workspace, payload)
      event = payload["event"] || {}
      subtype = event["subtype"]
      return unless SUPPORTED_SUBTYPES.include?(subtype)

      channel_id = event["channel"]
      return unless channel_id

      case subtype
      when Identifiers::MESSAGE_SUBTYPE_MESSAGE_CHANGED then handle_edit(workspace, channel_id, event)
      when Identifiers::MESSAGE_SUBTYPE_MESSAGE_DELETED then handle_delete(workspace, channel_id, event)
      else handle_new_message(workspace, channel_id, event)
      end
    end

    def self.handle_new_message(workspace, channel_id, event)
      incident = find_incident(workspace, channel_id)
      return unless incident

      message_ts = event["ts"]
      member = workspace.workspace_memberships.find_by(platform_user_id: event["user"])

      # Skip transcript ingest for bot messages -- they're better captured by
      # the structured timeline (our own bot's announcements) or by
      # integration-specific event handlers (Datadog alerts, PagerDuty acks).
      # Including bot prose in the transcript pollutes the Layer 2 narrative
      # summary. File uploads from bots still flow through handle_files so
      # archival + timeline events work.
      unless event["bot_id"].present? || event["app_id"].present?
        incident.incident_transcript_messages.create!(
          workspace: workspace,
          slack_ts: message_ts,
          slack_thread_ts: event["thread_ts"],
          slack_user_id: event["user"],
          workspace_membership: member,
          content: event["text"].to_s,
          posted_at: Time.at(message_ts.to_f)
        )
      end

      handle_files(workspace, channel_id, incident, event, member)
    rescue ActiveRecord::RecordNotUnique
      nil
    end
    private_class_method :handle_new_message

    def self.handle_edit(workspace, channel_id, event)
      incident = find_incident(workspace, channel_id)
      return unless incident

      inner = event["message"] || {}
      ts = inner["ts"]
      return unless ts

      message = incident.incident_transcript_messages.find_by(slack_ts: ts)
      message&.update!(content: inner["text"].to_s)
    end
    private_class_method :handle_edit

    def self.handle_delete(workspace, channel_id, event)
      incident = find_incident(workspace, channel_id)
      return unless incident

      ts = event["deleted_ts"]
      return unless ts

      message = incident.incident_transcript_messages.find_by(slack_ts: ts)
      message&.soft_delete!
    end
    private_class_method :handle_delete

    def self.find_incident(workspace, channel_id)
      workspace.incidents.in_channel(channel_id).recent.first
    end
    private_class_method :find_incident

    def self.handle_files(workspace, channel_id, incident, event, member)
      files = event["files"] || []
      return if files.empty?

      message_ts = event["ts"]
      thread_ts = event["thread_ts"] || message_ts

      files.each do |file|
        # Slack redelivers an event it did not get an answer to in time, so
        # the file id is the identity of the share, not the delivery.
        next if file_already_recorded?(incident, file["id"])

        permalink = message_permalink_for(workspace, channel_id, message_ts, file)

        incident_event = incident.incident_events.create!(
          event_type: IncidentEvent::MESSAGE_FILE_SHARED,
          actor: member,
          metadata: {
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
        )

        ArchiveIncidentFileJob.perform_later(incident_event.id, file)
      end
    end
    private_class_method :handle_files

    def self.file_already_recorded?(incident, slack_file_id)
      return false if slack_file_id.blank?

      incident.incident_events
        .where(event_type: IncidentEvent::MESSAGE_FILE_SHARED)
        .where("metadata @> ?", { slack_file_id: slack_file_id }.to_json)
        .exists?
    end
    private_class_method :file_already_recorded?

    def self.message_permalink_for(workspace, channel_id, message_ts, file)
      Events::Permalinks.fetch(workspace, channel_id, message_ts) || file["permalink"]
    end
    private_class_method :message_permalink_for
  end
end
