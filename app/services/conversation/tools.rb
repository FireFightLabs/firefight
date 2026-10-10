# What a conversation hands the agent. Everything else it opens with open_tools or loads with a skill. helpers is what
# the turn lends the helpers it hands checks to (Chat::Helpers::Share), nil where it has none to lend.
module Conversation::Tools
  def self.for(turn, offer:, helpers: nil)
    [
      Chat::Tools::Open.new(turn, offer: offer), Chat::Tools::UseSkill.new(turn, offer: offer), *Chat::Tools::Docs.all(turn), Chat::Tools::ReadResult.new(turn),
      *(Chat::Tools::Helpers.new(turn, share: helpers) if helpers),
      StartInvestigation.new(turn), RunRunbook.new(turn), StartWatch.new(turn), RepairWatch.new(turn), ExtendWatch.new(turn), StopWatch.new(turn),
      ListWatches.new(turn), *plans(turn),
      *Chat::Tools.memory(turn), Chat::Tools::CorrectMemory.new(turn), *Chat::Tools::Web.all(turn), *Chat::Tools::Terminal.all(turn),
      *Chat::Tools::OutsideCheck.all(turn)
    ]
  end

  def self.plans(turn) = [ MakePlan.new(turn), UpdatePlan.new(turn), FinishPlan.new(turn), CancelPlan.new(turn) ]

  # The person sees a plan as its checklist, so its tools are never shown as steps.
  def self.plan_tool_names = [ MakePlan::NAME, UpdatePlan::NAME, FinishPlan::NAME, CancelPlan::NAME ]
end
