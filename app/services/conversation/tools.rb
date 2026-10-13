# What a conversation hands the agent. Everything else it opens with open_tools, loads with a skill, or finds with its
# provider's own tool search (Chat::Tools.presented). helpers is what the turn lends the helpers it hands checks to
# (Chat::Helpers::Share), nil where it has none to lend. A share that says what specialists read adds ask_specialist,
# which is the one tool a chat that asks specialists holds beyond today's (Chat::Specialists).
module Conversation::Tools
  def self.for(turn, offer:, helpers: nil, presented: Chat::Tools::Presented.none)
    [
      Chat::Tools::Open.new(turn, offer: offer, presented: presented), Chat::Tools::UseSkill.new(turn, offer: offer), *Chat::Tools::Docs.all(turn), Chat::Tools::ReadResult.new(turn),
      *(Chat::Tools::Helpers.new(turn, share: helpers) if helpers), *(Chat::Tools::AskSpecialist.new(turn, share: helpers) if helpers&.specialists),
      Chat::Tools::Theories.new(turn), StartInvestigation.new(turn), RunRunbook.new(turn), StartWatch.new(turn), RepairWatch.new(turn), ExtendWatch.new(turn), StopWatch.new(turn),
      ListWatches.new(turn), *plans(turn),
      *Chat::Tools.memory(turn), *Chat::Tools::ProposeSkill.all(turn), Chat::Tools::CorrectMemory.new(turn), *Chat::Tools::Web.all(turn), *Chat::Tools::Terminal.all(turn),
      *Chat::Tools::OutsideCheck.all(turn), *Chat::Tools::Browser.all(turn)
    ]
  end

  def self.plans(turn) = [ MakePlan.new(turn), UpdatePlan.new(turn), FinishPlan.new(turn), CancelPlan.new(turn) ]

  # The person sees a plan as its checklist, so its tools are never shown as steps.
  def self.plan_tool_names = [ MakePlan::NAME, UpdatePlan::NAME, FinishPlan::NAME, CancelPlan::NAME ]
end
