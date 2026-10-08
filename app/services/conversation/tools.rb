# What a conversation hands the agent. Everything else it opens with open_tools or loads with a skill.
module Conversation::Tools
  def self.for(turn, offer:)
    [
      Chat::Tools::Open.new(turn, offer: offer), Chat::Tools::UseSkill.new(turn, offer: offer), *Chat::Tools::Docs.all(turn), Chat::Tools::ReadResult.new(turn),
      StartInvestigation.new(turn), RunRunbook.new(turn), StartWatch.new(turn), ExtendWatch.new(turn), StopWatch.new(turn), ListWatches.new(turn),
      *Chat::Tools.memory(turn), Chat::Tools::CorrectMemory.new(turn), *Chat::Tools::Web.all(turn)
    ]
  end
end
