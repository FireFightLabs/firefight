# Moves a step of a plan Halon keeps as it starts and ends, or replaces the steps not started yet. The person watches the
# checklist move with it.
class Conversation::Tools::UpdatePlan < Conversation::Tools::PlanTool
  NAME = "update_plan".freeze

  description "Update a plan as you work: mark a step running before you start it, and done, failed or skipped once it ends, " \
              "with what happened. A failed step says why, quoting the provider. A done check says what you read against " \
              "normal and whether the changes worked as verdict. A change that fails, or a check that finds the changes did " \
              "not work, stops the plan, and the person is offered Retry and Undo. Give revise to replace every step not " \
              "started yet when the plan has to change."

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "plan" => PLAN,
        "step" => { "type" => "integer", "description" => "The step's number" },
        "status" => { "type" => "string", "enum" => Chat::Plan::Step::STATUSES - [ Chat::Plan::Step::STATUS_NOT_STARTED ] },
        "note" => { "type" => "string",
                    "description" => "What happened, in a sentence: the result, why it failed quoting the provider, or for a check what " \
                                     "you read against normal (optional)" },
        "links" => { "type" => "array", "items" => { "type" => "string" },
                     "description" => "Pages that show it, such as the run or the deploy, as full addresses a result gave (optional)" },
        "verdict" => { "type" => "string", "enum" => Chat::Plan::Step::VERDICTS,
                       "description" => "A check only: whether the changes worked, or that nothing you can read could tell" },
        "undo" => { "type" => "string",
                    "description" => "A change only: its undo made exact from what it returned, such as the previous value or an id (optional)" },
        "revise" => { "type" => "array", "items" => STEP,
                      "description" => "Replaces every step not started yet, when the plan has to change (optional)" }
      }
    }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    plan = find_plan(given["plan"], Chat::Plan::OPEN)
    plan.revise!(given["revise"]) if given["revise"].present?
    if given["step"].present?
      refuse!("Give the step's status.") if given["status"].blank?
      plan.move_step!(given["step"], status: given["status"], note: given["note"], links: given["links"], verdict: given["verdict"],
                                     undo: given["undo"], read_since: ->(time) { Conversation::Plans.read_since?(chat, time) })
    elsif given["revise"].blank?
      refuse!("Give a step and its status, or revise.")
    end
    told(plan, said(plan.reload))
  rescue Chat::Plan::Refused => refused
    refused(tool_call, "Not updated. #{refused.message}")
  end

  private

  def said(plan)
    if plan.stopped?
      offers = plan.steps.any? { |step| step.change? && step.done? } ? "Retry and Undo" : "Retry"
      return "The plan stopped. #{plan.stop_reason} Tell the person what is done, what failed and why, and what has not started: " \
             "#{plan.standing} The plan card offers #{offers}."
    end
    return "Updated. Every step has ended, so finish it with finish_plan." if plan.steps.all?(&:ended?)

    "Updated."
  end
end
