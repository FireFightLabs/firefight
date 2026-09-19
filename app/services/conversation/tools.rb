# What a conversation hands the agent. Everything else it finds with find_tools.
module Conversation::Tools
  def self.for(turn, offer:)
    [ Chat::Tools::Find.new(turn, offer: offer), StartInvestigation.new(turn) ]
  end
end
