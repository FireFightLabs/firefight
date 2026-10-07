# A member refused a change for want of a pack, from the refusal to an admin giving it. The refusal is shown in the chat
# and its Slack thread with Ask an admin. Asking direct messages every workspace admin with Give pack, at most once a day
# for the same member and pack, and the Permissions screen lists what is waiting. Giving goes through the same grant as
# the Permissions screen.
class PackRequestService
  ASKED = "Asked %<admins>s for %<pack>s.".freeze
  NO_ADMIN_REACHED = "No admin could be reached by direct message, so the request waits on the Permissions screen.".freeze

  # Shows a new refusal where the chat lives. The dashboard card reads it from the chat, a thread gets a message.
  def self.refused!(refusal)
    Conversation::LiveDelivery.pack_refused(refusal.conversation)
    conversation = refusal.conversation
    return if conversation.thread_id.blank?

    posted = WorkspaceAdapter.for(refusal.workspace).post_pack_refusal(channel_id: conversation.channel_id, thread_id: conversation.thread_id, refusal: refusal)
    refusal.update_columns(message_channel_id: posted[:channel_id], message_id: posted[:message_id])
  rescue AdapterError => error
    Rails.logger.warn({ event: "pack_refusal.unposted", pack_refusal_id: refusal.id, error: error.class.name }.to_json)
  end

  # What the person is told, as a Result that says whether the admins were asked.
  def self.ask!(request, by:)
    blocked = request.ask_blocked_reason(by)
    return Result.new(ok: false, words: blocked) if blocked
    return Result.new(ok: false, words: request.reload.ask_blocked_reason || "The admins were already asked.") unless request.claim_ask!

    reached = notify_admins(request)
    redraw_refusals(request)
    Result.new(ok: true, words: [ format(ASKED, admins: Ability::PackRequest.admin_names(request.workspace).presence || "the workspace admins",
                                         pack: request.role.name), (NO_ADMIN_REACHED unless reached) ].compact.join(" "))
  end

  def self.give!(request, by:)
    blocked = request.give_blocked_reason
    if blocked
      redraw_requests(request)
      return Result.new(ok: false, words: blocked)
    end

    request.give!(by: by)
    answered!(request)
    Result.new(ok: true, words: "#{request.requester.display_name} was given #{request.role.name}.")
  end

  def self.dismiss!(request, by:)
    return Result.new(ok: false, words: "This request was already answered.") unless request.dismiss!(by: by)

    answered!(request)
    Result.new(ok: true, words: "#{request.requester.display_name}'s request for #{request.role.name} was dismissed.")
  end

  Result = Data.define(:ok, :words)

  # A pack given on the Permissions screen rather than from the request still settles it where it was shown.
  def self.settled!(request) = answered!(request)

  # An admin gave the pack or dismissed the request. The admins' messages and the refusals are redrawn, the member is
  # told by direct message, and each Slack thread the refusal was in gets a short note.
  def self.answered!(request)
    redraw_requests(request)
    redraw_refusals(request)
    adapter = WorkspaceAdapter.for(request.workspace)
    tell_requester(adapter, request)
    note_in_threads(adapter, request)
  end

  def self.tell_requester(adapter, request)
    return if request.requester.platform_user_id.blank?

    adapter.post_pack_answer_to_user(user_id: request.requester.platform_user_id, pack_request: request)
  rescue AdapterError => error
    Rails.logger.warn({ event: "pack_request.answer_undelivered", pack_request_id: request.id, error: error.class.name }.to_json)
  end
  private_class_method :tell_requester

  def self.note_in_threads(adapter, request)
    request.refusals.includes(chat: :owner).find_each do |refusal|
      conversation = refusal.conversation
      next if conversation.thread_id.blank?

      adapter.post_pack_answer(channel_id: conversation.channel_id, thread_id: conversation.thread_id, pack_request: request)
    rescue AdapterError => error
      Rails.logger.warn({ event: "pack_request.note_undelivered", pack_refusal_id: refusal.id, error: error.class.name }.to_json)
    end
  end
  private_class_method :note_in_threads

  # True when at least one admin was sent the request.
  def self.notify_admins(request)
    adapter = WorkspaceAdapter.for(request.workspace)
    Ability::PackRequest.admins_of(request.workspace).select { |admin| admin.platform_user_id.present? }.count do |admin|
      posted = adapter.post_pack_request_to_user(user_id: admin.platform_user_id, pack_request: request)
      request.add_notification!(channel_id: posted[:channel_id], message_id: posted[:message_id])
      true
    rescue AdapterError => error
      Rails.logger.warn({ event: "pack_request.undelivered", pack_request_id: request.id, error: error.class.name }.to_json)
      false
    end.positive?
  end
  private_class_method :notify_admins

  def self.redraw_requests(request)
    adapter = WorkspaceAdapter.for(request.workspace)
    request.reload.notifications.each do |notification|
      adapter.update_pack_request(channel_id: notification["channel_id"], message_id: notification["message_id"], pack_request: request)
    rescue AdapterError => error
      Rails.logger.warn({ event: "pack_request.redraw_failed", pack_request_id: request.id, error: error.class.name }.to_json)
    end
  end
  private_class_method :redraw_requests

  def self.redraw_refusals(request)
    adapter = WorkspaceAdapter.for(request.workspace)
    request.refusals.includes(chat: :owner).find_each do |refusal|
      Conversation::LiveDelivery.pack_refused(refusal.conversation)
      next if refusal.message_id.blank?

      adapter.update_pack_refusal(channel_id: refusal.message_channel_id, message_id: refusal.message_id, refusal: refusal)
    rescue AdapterError => error
      Rails.logger.warn({ event: "pack_refusal.redraw_failed", pack_refusal_id: refusal.id, error: error.class.name }.to_json)
    end
  end
  private_class_method :redraw_refusals
end
