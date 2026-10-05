# Files a person attaches in the chat's composer, uploaded as they are added and sent with the next message. A file is
# read back only by whoever may read the chat it went with.
class AgentChatAttachmentsController < InertiaController
  # Uploading is part of asking, which spends money.
  authorizes Ability::Action::RESOURCE_INVESTIGATIONS, create: %i[create destroy]
  authorizes Ability::Action::RESOURCE_CHATS, read: %i[show]

  before_action :require_agent!

  NO_FILE = "Choose a file to attach.".freeze
  # A file that can only be shown is never handed to the browser as something to run.
  SHOWN_INLINE = Chat::Attachment::IMAGE_TYPES

  def create
    upload = params[:file]
    return refuse(NO_FILE) unless upload.respond_to?(:read)

    name = Chat::Attachment.clean_name(upload.original_filename)
    return refuse(Chat::Attachment.too_large(name, upload.size, Chat::Attachment::LARGEST)) if upload.size > Chat::Attachment::LARGEST

    file = Chat::Attachment.take!(workspace: current_workspace, uploaded_by: current_membership, filename: name, bytes: upload.read)
    render json: AgentChatAttachmentSerializer.one(file), status: :created
  rescue Chat::Attachment::Refused => refused
    refuse(refused.message)
  end

  def show
    file = current_workspace.chat_attachments.find(params[:id])
    raise ActiveRecord::RecordNotFound unless file.readable_by?(current_membership) && file.blob

    inline = SHOWN_INLINE.include?(file.content_type)
    response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "private, no-store"
    send_data file.bytes, filename: file.filename, type: file.content_type, disposition: inline ? "inline" : "attachment"
  end

  # Taking a file off before sending it deletes the upload.
  def destroy
    current_workspace.chat_attachments.unsent.where(uploaded_by: current_membership).find(params[:id]).destroy!
    head :no_content
  end

  private

  def refuse(sentence) = render(json: { error: sentence }, status: :unprocessable_content)

  def require_agent!
    return if Investigation.available_for?(current_workspace)

    render json: { error: Investigation.unavailable_reason(current_workspace) }, status: :forbidden
  end
end
