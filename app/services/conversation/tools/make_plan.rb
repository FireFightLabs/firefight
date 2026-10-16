# Makes the short plan Halon keeps for a request that takes more than one step, which the person sees as a checklist.
# A later time is a workflow, so a run_at sent anyway is refused with where to make it.
class Conversation::Tools::MakePlan < Conversation::Tools::PlanTool
  NAME = "make_plan".freeze

  description "Make a plan for a request that takes more than one step or spans more than one system, before the first " \
              "step, such as a release, a migration or a fix across systems. A clear request about one system that takes one " \
              "step needs none, and a request that could mean more than one thing is settled with the person first. Give the " \
              "goal in the person's words and a step per action naming where it happens, then say the plan back in two short " \
              "lines and start, since each change asks the person when it runs. The person sees it as a checklist that moves " \
              "as you update it. Each change carries its undo, written now. A plan that changes anything ends with a check " \
              "step that reads health, error rate and latency against normal. A plan is for what you do now. Something the " \
              "person wants done at a later time is a workflow, made with create_workflow."

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "goal" => { "type" => "string", "description" => "What the person wants done, in their own words, such as release main to production" },
        "steps" => { "type" => "array", "items" => STEP, "description" => "The steps in order, #{Chat::Plan::MIN_STEPS} to #{Chat::Plan::MAX_STEPS}" }
      },
      "required" => %w[goal steps]
    }
  end

  def call(tool_call: nil, **arguments)
    given = arguments.deep_stringify_keys
    refuse!("Plans are kept in a chat, and this one has none.") unless chat
    refuse!(LATER_IS_A_WORKFLOW) if given["run_at"].present?

    plan = Chat::Plan.make!(chat: chat, made_by: @turn.asker, goal: given["goal"], steps: given["steps"])
    told(plan, MADE)
  rescue Chat::Plan::Refused => refused
    refused(tool_call, "Not made. #{refused.message}")
  end

  # Something to do at a later time is a workflow, made with create_workflow, so there is one scheduler.
  LATER_IS_A_WORKFLOW = "Something to do at a later time is a workflow here. Make it with create_workflow and a once_at trigger instead, and " \
                        "keep plans for what you do now.".freeze

  MADE = "Plan made. Say it to the person in two short lines, then carry it out, marking each step running and then done, " \
         "failed or skipped with update_plan. A change still asks the person as usual.".freeze
end
