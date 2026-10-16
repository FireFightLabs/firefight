# Makes the short plan Halon keeps for a request that takes more than one step, which the person sees as a checklist.
# A later time is refused, since something to do then is a workflow.
class Conversation::Tools::MakePlan < Conversation::Tools::PlanTool
  NAME = "make_plan".freeze

  description "Make a plan for a request that takes more than one step or spans more than one system, before the first " \
              "step, such as a release, a migration or a fix across systems. A clear request about one system that takes one " \
              "step needs none, and a request that could mean more than one thing is settled with the person first. Give the " \
              "goal in the person's words and a step per action naming where it happens, then say the plan back in two short " \
              "lines and start, since each change asks the person when it runs. The person sees it as a checklist that moves " \
              "as you update it. Each change carries its undo, written now. A plan that changes anything ends with a check " \
              "step that reads health, error rate and latency against normal. Give run_at only when the person asked for it " \
              "to happen at a later time: the plan then waits for them to approve it, and at that time Halon reads how things " \
              "stand and runs it as them. A time inside a freeze is refused, so offer one after it."

  def name = NAME

  def parameters_schema
    {
      "type" => "object",
      "properties" => {
        "goal" => { "type" => "string", "description" => "What the person wants done, in their own words, such as release main to production" },
        "steps" => { "type" => "array", "items" => STEP, "description" => "The steps in order, #{Chat::Plan::MIN_STEPS} to #{Chat::Plan::MAX_STEPS}" },
        "run_at" => { "type" => "string",
                      "description" => "Only when the person asked for a later time: when to run it, as a local date and time such as " \
                                       "2026-10-11T06:00, worked out from today's date (optional)" },
        "time_zone" => { "type" => "string",
                         "description" => "The time zone run_at is in, such as Europe/Berlin, when the person named one. Left out, it is " \
                                          "their own time zone (optional)" }
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
