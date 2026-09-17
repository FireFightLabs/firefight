# What a dashboard chat sends while the agent is working. A personal chat belongs to one person,
# so the socket is refused for anyone else.
class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.personal.find_by(id: params[:id])
    return reject unless watchable?(conversation)

    stream_for conversation
  end

  private

  def watchable?(conversation)
    conversation.present? && conversation.started_by.present? &&
      conversation.started_by.user_id == current_user.id
  end
end
