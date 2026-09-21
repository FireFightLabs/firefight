# What a conversation hands the agent. Everything else it opens with open_tools.
module Conversation::Tools
  def self.for(turn, offer:)
    [ Chat::Tools::Open.new(turn, offer: offer), Chat::Tools::ReadResult.new(turn), StartInvestigation.new(turn) ]
  end
end
