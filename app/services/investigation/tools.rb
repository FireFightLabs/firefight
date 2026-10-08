# What an investigation hands the agent. Everything else it opens with open_tools or loads with a skill.
module Investigation::Tools
  def self.for(investigation, offer:)
    [ Chat::Tools::Open.new(investigation, offer: offer), Chat::Tools::UseSkill.new(investigation, offer: offer), *Chat::Tools::Docs.all(investigation),
      Chat::Tools::ReadResult.new(investigation),
      RecordHypothesis.new(investigation), Conclude.new(investigation), *Chat::Tools.memory(investigation), *Chat::Tools::Web.all(investigation) ]
  end
end
