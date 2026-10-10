# A plan Halon keeps in this chat, as a checklist: its goal, each step as it stands, when it runs, and how it ended. What
# the viewer may press ships as offers with a blocked reason each, so the card decides nothing.
class AgentChatPlanSerializer < BaseSerializer
  object_as :plan

  type :string
  def id
    plan.id
  end

  type :string
  def goal
    plan.goal
  end

  type Chat::Plan::STATUSES.map(&:inspect).join(" | ")
  def status
    plan.status
  end

  # Such as "Plan stopped" or "Undo in progress".
  type :string
  def heading
    plan.heading
  end

  # Such as "2 of 5 steps done." or "Runs Saturday 11 October at 06:00 CEST, approved by Ana."
  type :string
  def progress
    plan.progress_words
  end

  # The plan this one undoes, by its goal.
  type :string, optional: true
  def undoes
    plan.undoes&.goal
  end

  # Why it stopped or was cancelled, which for a scheduled run that did not start is what Halon read just before.
  type :string, optional: true
  def stop_reason
    plan.stop_reason if Chat::Plan::ENDED.include?(plan.status)
  end

  type :string, optional: true
  def outcome
    plan.outcome
  end

  type :string, optional: true
  def next_step
    plan.next_step
  end

  type "string[]"
  def links
    plan.links
  end

  # Placed among the chat's messages by when it last moved, so a plan that runs on sits where the person is reading.
  type :string
  def at
    plan.moved_at.utc.iso8601(3)
  end

  type "{ id: string; position: number; kind: #{Chat::Plan::Step::KINDS.map(&:inspect).join(' | ')}; description: string; place: string | null; " \
       "status: #{Chat::Plan::Step::STATUSES.map(&:inspect).join(' | ')}; note: string | null; tool: string | null; " \
       "verdict: #{Chat::Plan::Step::VERDICTS.map(&:inspect).join(' | ')} | null; undo: string | null; links: string[] }[]"
  def steps
    plan.steps.map do |step|
      { id: step.id, position: step.position, kind: step.kind, description: step.description, place: step.place, status: step.status,
        note: step.note, verdict: step.verdict, undo: step.undo, links: step.links, tool: (Chat::Tools.title_for(step.tool, plan.workspace) if step.tool) }
    end
  end

  type "{ action: #{Chat::Plan::ACTIONS.map(&:inspect).join(' | ')}; blockedReason: string | null }[]"
  def offers
    plan.offers.map { |action| { action: action, blockedReason: plan.blocked_reason(action, options[:member]) } }
  end
end
