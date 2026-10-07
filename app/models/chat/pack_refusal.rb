# A change Halon was refused in a chat because the person asking holds no pack for it. The chat shows it as a card, and a
# chat in a Slack thread posts it there too, each with Ask an admin. One per chat and pack, however often Halon is refused.
class Chat::PackRefusal < ApplicationRecord
  belongs_to :chat
  belongs_to :pack_request, class_name: "Ability::PackRequest"

  delegate :requester, :role, :workspace, to: :pack_request

  # The refusal for this chat and pack, and whether it is new, so it is posted once.
  def self.record!(chat:, pack_request:, tool_call_id:)
    found = find_by(chat: chat, pack_request: pack_request)
    return [ found, false ] if found

    [ create!(chat: chat, pack_request: pack_request, tool_call_id: tool_call_id), true ]
  rescue ActiveRecord::RecordNotUnique
    [ find_by!(chat: chat, pack_request: pack_request), false ]
  end

  def conversation = chat.owner

  # The words on the card and the Slack message.
  def headline = "#{requester.display_name} does not have permission to make this change."

  def body = [ "It needs the #{role.name} pack.", Ability::PackRequest.admins_sentence(workspace) ].compact.join(" ")

  # Said once the admins were asked, and then how they answered.
  def asked_line
    request = pack_request
    return "#{request.answered_by_name} gave #{requester.display_name} this pack. Ask Halon again." if request.given_at
    return "#{request.answered_by_name} dismissed the request." if request.dismissed_at
    return "Asked the admins at #{request.requested_at.utc.strftime('%H:%M UTC')}." if request.waiting?

    nil
  end
end
