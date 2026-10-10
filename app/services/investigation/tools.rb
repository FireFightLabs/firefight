# What an investigation hands the agent. Everything else it opens with open_tools or loads with a skill. helpers is what
# the run lends the helpers it hands checks to (Chat::Helpers::Share), nil where it has none to lend.
module Investigation::Tools
  def self.for(investigation, offer:, helpers: nil)
    [ Chat::Tools::Open.new(investigation, offer: offer), Chat::Tools::UseSkill.new(investigation, offer: offer), *Chat::Tools::Docs.all(investigation),
      Chat::Tools::ReadResult.new(investigation), *(Chat::Tools::Helpers.new(investigation, share: helpers) if helpers),
      RecordHypothesis.new(investigation), Conclude.new(investigation), *Chat::Tools.memory(investigation), *Chat::Tools::Web.all(investigation),
      *Chat::Tools::Terminal.all(investigation), *Chat::Tools::OutsideCheck.all(investigation) ]
  end
end
