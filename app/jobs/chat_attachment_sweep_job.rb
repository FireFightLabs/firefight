# Lets go of files someone uploaded for a message and never sent.
class ChatAttachmentSweepJob < ApplicationJob
  queue_as :background

  def perform
    Chat::Attachment.abandoned.find_each(&:destroy)
  end
end
