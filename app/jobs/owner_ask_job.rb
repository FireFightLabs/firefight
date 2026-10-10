# Asks the owner of what a confirmed call would stop, in their direct messages, away from the click.
class OwnerAskJob < ApplicationJob
  queue_as :default

  def perform(owner_ask_id)
    ask = Chat::OwnerAsk.find_by(id: owner_ask_id)
    Conversation::OwnerAsks.deliver!(ask) if ask
  end
end
