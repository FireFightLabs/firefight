# Hands a file a person gave Halon back to the browser, decrypted, for whichever page decided they may read it. An image
# is shown, anything else is downloaded, and nothing is sniffed or run.
module ServesChatAttachment
  extend ActiveSupport::Concern

  # A file that can only be shown is never handed to the browser as something to run.
  SHOWN_INLINE = Chat::Attachment::IMAGE_TYPES

  private

  def send_chat_attachment(file)
    raise ActiveRecord::RecordNotFound unless file.sealed.attached?

    inline = SHOWN_INLINE.include?(file.content_type)
    response.headers["Content-Security-Policy"] = "default-src 'none'; sandbox"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Cache-Control"] = "private, no-store"
    send_data file.bytes, filename: file.filename, type: file.content_type, disposition: inline ? "inline" : "attachment"
  end
end
