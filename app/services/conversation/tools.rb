# What a conversation hands the agent. Everything else it finds with find_tools.
module Conversation::Tools
  def self.for(conversation, offer:)
    [ Chat::Tools::Find.new(conversation, offer: offer), StartInvestigation.new(conversation) ]
  end
end
