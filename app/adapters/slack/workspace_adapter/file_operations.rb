# Files someone shared in a message, downloaded with the bot's token. Slack's file objects never leave this module.
module Slack::WorkspaceAdapter::FileOperations
  extend ActiveSupport::Concern

  NOT_DOWNLOADED = "Firefight could not download it from Slack.".freeze
  NO_PERMISSION = "Slack did not let Firefight download it. The Firefight app needs the files:read permission, which " \
                  "reinstalling it from Settings grants.".freeze
  # Slack names a file it will only describe on request, such as one shared from another workspace.
  DESCRIBED_ON_REQUEST = "check_file_info".freeze

  def fetch_shared_files(files:, max_bytes:)
    Array(files).map { |file| fetch_shared_file(file.to_h.deep_stringify_keys, max_bytes) }
  end

  private

  def fetch_shared_file(file, max_bytes)
    file = described(file)
    name = file["name"].presence || file["title"].presence || "file"
    size = file["size"].to_i
    return shared(name, size, too_large: true) if size > max_bytes

    url = file["url_private_download"].presence || file["url_private"].presence
    return shared(name, size, failure: NOT_DOWNLOADED) if url.blank?

    body = translate_errors { Slack::Client.download_file(workspace: @workspace, url: url)[:body] }
    return shared(name, body.bytesize, too_large: true) if body.bytesize > max_bytes

    PlatformAdapter::SharedFile.new(name: name, byte_size: body.bytesize, body: body, too_large: false, failure: nil)
  rescue AdapterError => error
    Rails.logger.warn({ event: "slack.shared_file_not_downloaded", workspace_id: @workspace.id, error: error.class.name }.to_json)
    shared(name || file["name"].presence || "file", size.to_i, failure: missing_permission?(error) ? NO_PERMISSION : NOT_DOWNLOADED)
  end

  def described(file)
    return file unless file["file_access"] == DESCRIBED_ON_REQUEST || (file["url_private"].blank? && file["url_private_download"].blank?)
    return file if file["id"].blank?

    translate_errors { Slack::Client.file_info(workspace: @workspace, file_id: file["id"]) }.to_h.deep_stringify_keys
  end

  def missing_permission?(error)
    error.is_a?(AdapterError::MissingPermission) || error.message.include?("files:read")
  end

  def shared(name, size, too_large: false, failure: nil)
    PlatformAdapter::SharedFile.new(name: name, byte_size: size, body: nil, too_large: too_large, failure: failure)
  end
end
