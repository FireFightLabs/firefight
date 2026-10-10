# Makes the short plan Halon keeps for a request that takes more than one step, which the person sees as a checklist.
# With a time, the plan waits for the person to approve it and then runs at that time.
class Conversation::Tools::MakePlan < Conversation::Tools::PlanTool
  NAME = "make_plan".freeze

  description "Make a plan for a request that takes more than one step, before the first one, such as a release, a migration " \
              "or a fix across systems. The person sees it as a checklist that moves as you update it. Each change carries its " \
              "undo, written now. A plan that changes anything ends with a check step that reads health, error rate and latency " \
              "against normal. Give run_at only when the person asked for it to happen at a later time: the plan then waits " \
              "for them to approve it, and at that time Halon reads how things stand and runs it as them."

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

    run_at, zone = (scheduled_time(given["run_at"], given["time_zone"]) if given["run_at"].present?)
    callable!(given["steps"]) if run_at
    plan = Chat::Plan.make!(chat: chat, made_by: @turn.asker, goal: given["goal"], steps: given["steps"], run_at: run_at, time_zone: zone)
    told(plan, plan.proposed? ? proposed_words(plan) : MADE)
  rescue Chat::Plan::Refused => refused
    refused(tool_call, "Not made. #{refused.message}")
  end

  MADE = "Plan made. Say it to the person in two short lines, then carry it out, marking each step running and then done, " \
         "failed or skipped with update_plan. A change still asks the person as usual.".freeze

  private

  def proposed_words(plan)
    "Proposed for #{plan.run_at_words}. Nothing runs until a person approves it with Schedule on the plan card. At that time Halon " \
      "reads how things stand, and runs it as whoever approved it only if nothing moved and no freeze covers it. Tell them so in a sentence."
  end

  def scheduled_time(asked, zone_name)
    refuse!("A plan with a time needs a person to approve it, and nobody in this chat can.") unless schedulable?

    zone_name = zone_name.to_s.strip.presence || Conversation::Plans.time_zone_of(@turn.asker, @turn.workspace)
    refuse!("Their time zone is not known. Ask the person which time zone they mean, then give it as time_zone.") if zone_name.blank?

    zone = ActiveSupport::TimeZone[zone_name]
    refuse!("#{zone_name} is not a time zone. Give one such as Europe/Berlin.") unless zone

    time = zone.parse(asked.to_s)
    refuse!("#{asked} is not a date and time. Give one such as 2026-10-11T06:00.") unless time
    [ time, zone.tzinfo.name ]
  rescue ArgumentError
    refuse!("#{asked} is not a date and time. Give one such as 2026-10-11T06:00.")
  end

  # A person approves a scheduled plan's changes by the tools they name, so each must be one this person may call that
  # changes something.
  def callable!(steps)
    named = Array(steps).filter_map { |step| step.to_h.stringify_keys.then { |asked| asked["tool"].to_s.strip.presence if asked["kind"] == Chat::Plan::Step::KIND_CHANGE } }
    return if named.empty?

    callable = Chat::Tools.catalog(@turn).select { |entry| entry.state == Chat::Tools::STATE_READY }.map { |entry| entry.name.to_s }
    unknown = named.uniq.reject { |name| callable.include?(name) && Chat::Tools.kind(name, @turn.workspace) == Chat::Tools::KIND_ACT }
    refuse!("#{unknown.to_sentence} #{unknown.one? ? 'is not a tool' : 'are not tools'} #{@turn.asker_name} may call that changes something. Name each change's tool as you call it.") if unknown.any?
  end

  def schedulable?
    conversation = @turn.conversation
    @turn.asker.is_a?(WorkspaceMembership) && !conversation.mcp?
  end
end
