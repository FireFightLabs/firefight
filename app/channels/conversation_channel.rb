# What a dashboard chat sends while the agent works. A personal chat belongs to one person, so
# nobody else may watch it.
class ConversationChannel < ApplicationCable::Channel
  def subscribed
    conversation = Conversation.find_by(id: params[:id])
    return reject unless conversation&.watchable_by?(current_user)

    stream_for conversation
  end
end
