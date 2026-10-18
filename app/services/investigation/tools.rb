# What an investigation hands the agent. Everything else it opens with open_tools, loads with a skill, or finds with its
# provider's own tool search (Chat::Tools.presented). helpers is what the run lends the helpers it hands checks to
# (Chat::Helpers::Share), nil where it has none to lend.
module Investigation::Tools
  def self.for(investigation, offer:, helpers: nil, presented: Chat::Tools::Presented.none)
    [ Chat::Tools::Open.new(investigation, offer: offer, presented: presented), Chat::Tools::UseSkill.new(investigation, offer: offer), *Chat::Tools::Docs.all(investigation),
      Chat::Tools::ReadResult.new(investigation), *(Chat::Tools::Helpers.new(investigation, share: helpers) if helpers && Chat::Helpers.offered?),
      *own_tools(investigation), *Chat::Tools.memory(investigation), *Chat::Tools::Web.all(investigation),
      *Chat::Tools::Terminal.all(investigation), *Chat::Tools::OutsideCheck.all(investigation),
      *Chat::Tools::Browser.all(investigation) ]
  end

  # A scheduled check notes problems and finishes, where an investigation weighs theories and concludes.
  def self.own_tools(investigation)
    return [ NoteProblem.new(investigation), FinishCheck.new(investigation) ] if investigation.scheduled?

    [ RecordHypothesis.new(investigation), Conclude.new(investigation) ]
  end
end
