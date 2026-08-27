module Slack::WorkspaceAdapter::UserOperations
  extend ActiveSupport::Concern

  def resolve_user_ids_from_handles(handles:)
    normalized_handles = Array(handles).map { |handle| normalize_handle(handle) }.reject(&:blank?).uniq
    return { resolved_user_ids: [], unresolved_handles: [] } if normalized_handles.empty?

    alias_to_user_id = {}
    Slack::Client.list_users(workspace: @workspace).each do |member|
      next if member[:deleted]
      next if member[:is_bot]

      user_id = member[:id].to_s
      next if user_id.blank?

      aliases_for_member(member).each do |handle_alias|
        alias_to_user_id[handle_alias] ||= user_id
      end
    end

    resolved = []
    unresolved = []
    normalized_handles.each do |handle|
      user_id = alias_to_user_id[handle]
      if user_id
        resolved << user_id
      else
        unresolved << handle
      end
    end

    { resolved_user_ids: resolved.uniq, unresolved_handles: unresolved }
  end

  def archive_slack_file(incident_event:, slack_file:)
    download_url = slack_file["url_private_download"] || slack_file["url_private"]
    return { archived: false } if download_url.blank?

    translate_errors do
      payload = Slack::Client.download_file(workspace: @workspace, url: download_url)
      filename = slack_file["name"].presence || "incident-file"
      content_type = slack_file["mimetype"].presence || payload[:content_type]

      incident_event.artifact.attach(
        io: StringIO.new(payload[:body]),
        filename: filename,
        content_type: content_type
      )

      blob = incident_event.artifact.blob

      {
        archived: true,
        object_key: blob.key,
        blob_id: blob.id,
        byte_size: blob.byte_size,
        checksum: blob.checksum
      }
    end
  end

  private

  def normalize_handle(handle)
    handle.to_s.downcase.strip.delete_prefix("@")
  end

  def aliases_for_member(member)
    profile = member[:profile] || {}
    aliases = []

    aliases << normalize_handle(member[:name])
    aliases << normalize_handle(profile[:display_name])
    aliases << normalize_handle(profile[:display_name_normalized])
    aliases << normalize_handle(profile[:real_name])
    aliases << normalize_handle(profile[:real_name_normalized])

    email_local = profile[:email].to_s.split("@").first
    aliases << normalize_handle(email_local)

    aliases.compact.reject(&:blank?).uniq
  end
end
