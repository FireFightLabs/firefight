# Files someone shared on a platform in the message that asked Halon something, fetched through the adapter and taken the
# same way an upload from the dashboard is. A file that cannot be taken is kept with why, so Halon says so.
class Conversation::SharedFiles
  def self.receive(workspace:, files:, sender:)
    return [] if files.blank?

    fetched = workspace.adapter.fetch_shared_files(files: files, max_bytes: Chat::Attachment::LARGEST)
    fetched.each_with_index.map do |file, index|
      next unread(workspace, sender, file, Chat::Attachment::TOO_MANY) if index >= Chat::Attachment::MAX_PER_MESSAGE

      take(workspace, sender, file)
    end
  end

  def self.take(workspace, sender, file)
    return unread(workspace, sender, file, Chat::Attachment.too_large(file.name, file.byte_size, Chat::Attachment::LARGEST)) if file.too_large
    return unread(workspace, sender, file, file.failure) if file.body.nil?

    Chat::Attachment.take!(workspace: workspace, uploaded_by: sender, filename: file.name, bytes: file.body)
  rescue Chat::Attachment::Refused => refused
    unread(workspace, sender, file, refused.message)
  end
  private_class_method :take

  def self.unread(workspace, sender, file, why)
    Chat::Attachment.unread!(workspace: workspace, uploaded_by: sender, filename: file.name, byte_size: file.byte_size, refusal: why)
  end
  private_class_method :unread
end
