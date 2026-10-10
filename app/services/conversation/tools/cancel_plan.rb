# Ends a plan the person no longer wants, including one waiting for its time, so nothing in it runs.
class Conversation::Tools::CancelPlan < Conversation::Tools::PlanTool
  NAME = "cancel_plan".freeze

  description "Cancel a plan when the person no longer wants it, or before replacing it with a different one. A scheduled plan " \
              "then never runs. What already ran stays as it is."

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "plan" => PLAN,
        "reason" => { "type" => "string", "description" => "Why, in a short sentence, such as The person asked to release on Monday instead" }
      },
      "required" => %w[reason]
    }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    plan = find_plan(given["plan"], Chat::Plan::OPEN)
    refuse!("#{plan.goal_named} has already ended.") unless plan.cancel!(reason: Chat::Plan.sentence(given["reason"].to_s.strip.presence || "Cancelled"))
    told(plan, "Cancelled. Tell the person in a few words.")
  rescue Chat::Plan::Refused => refused
    refused(tool_call, "Not cancelled. #{refused.message}")
  end
end
