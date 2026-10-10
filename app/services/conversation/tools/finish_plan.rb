# Ends a plan once its last step ended, with what came of it, the pages that show it and the most useful next step.
class Conversation::Tools::FinishPlan < Conversation::Tools::PlanTool
  NAME = "finish_plan".freeze

  description "Finish a plan once every step has ended. A plan that changed something finishes only after its check read that " \
              "it worked. Give what came of it against the goal, the pages that show it, and the most useful next step, then " \
              "report the same to the person with those links and offer to take that step."

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "plan" => PLAN,
        "outcome" => { "type" => "string", "description" => "What came of it against the goal, in a sentence or two, with the evidence" },
        "next_step" => { "type" => "string", "description" => "The most useful next step, as an offer, such as Shall I watch the error rate for an hour?" },
        "links" => { "type" => "array", "items" => { "type" => "string" },
                     "description" => "Pages that show the outcome, such as the run, the deploy or the dashboard, as full addresses a result gave" }
      },
      "required" => %w[outcome next_step]
    }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    plan = find_plan(given["plan"], [ Chat::Plan::STATUS_ACTIVE ])
    plan.finish!(outcome: given["outcome"], next_step: given["next_step"], links: given["links"])
    told(plan, "Finished. Now report it to the person: the outcome against their goal, the links, and the next step as an offer.")
  rescue Chat::Plan::Refused => refused
    refused(tool_call, "Not finished. #{refused.message}")
  end
end
