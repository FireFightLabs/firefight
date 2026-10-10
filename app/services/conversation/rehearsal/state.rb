# What Firefight's own stateful tools hold in a replay: the watches and plans Halon made in it. A recorded answer can
# never show a change Halon makes in the run, so these tools answer from this state instead. A watch's step is read
# through the scenario's own answers, as the watch would read the provider live, so a watch that follows the wrong
# thing says it found nothing, and one Halon repaired says what it finds now.
class Conversation::Rehearsal::State
  WATCH_TOOLS = [
    Conversation::Tools::StartWatch.tool_name, Conversation::Tools::RepairWatch.tool_name, Conversation::Tools::ExtendWatch.tool_name,
    Conversation::Tools::StopWatch.tool_name, Conversation::Tools::ListWatches.tool_name
  ].freeze
  PLAN_TOOLS = [
    Conversation::Tools::MakePlan::NAME, Conversation::Tools::UpdatePlan::NAME, Conversation::Tools::FinishPlan::NAME,
    Conversation::Tools::CancelPlan::NAME
  ].freeze
  TOOLS = (WATCH_TOOLS + PLAN_TOOLS).freeze

  # What a watch step reads when no answer of the scenario matches it, the state live calls following nothing.
  NOTHING = "found nothing to follow yet, waiting".freeze
  READ_SHOWN = 240

  Watch = Struct.new(:id, :title, :purpose, :steps, :minutes, keyword_init: true)
  Plan = Struct.new(:id, :goal, :steps, :status, :outcome, keyword_init: true)

  def initialize(bench_case, used, ran)
    @case = bench_case
    @used = used
    @ran = ran
    @watches = []
    @plans = []
  end

  def handles?(name) = TOOLS.include?(name)

  def call(name, arguments)
    given = arguments.deep_stringify_keys
    case name
    when Conversation::Tools::StartWatch.tool_name then start_watch(given)
    when Conversation::Tools::RepairWatch.tool_name then repair_watch(given)
    when Conversation::Tools::ExtendWatch.tool_name then extend_watch(given)
    when Conversation::Tools::StopWatch.tool_name then stop_watch(given)
    when Conversation::Tools::ListWatches.tool_name then list_watches(given)
    when Conversation::Tools::MakePlan::NAME then make_plan(given)
    when Conversation::Tools::UpdatePlan::NAME then update_plan(given)
    when Conversation::Tools::FinishPlan::NAME then finish_plan(given)
    when Conversation::Tools::CancelPlan::NAME then cancel_plan(given)
    end
  end

  private

  def start_watch(given)
    watch = Watch.new(id: "W#{@watches.size + 1}", title: given["title"].to_s, purpose: given["purpose"].to_s,
                      steps: Array(given["steps"]).map(&:to_h), minutes: given["minutes"])
    @watches << watch
    "Watching \"#{watch.title}\" (watch #{watch.id}). #{steps_of(watch)}\nI will report each step as it passes and when it ends."
  end

  def repair_watch(given)
    watch = find_watch(given["watch"])
    return "There is no watch called #{given['watch']} in this chat. #{list_watches({})}" unless watch
    return stop_watch("watch" => watch.id) if given["give_up"]

    index = step_index(watch, given["step"])
    repaired = given.slice("capability", "tool", "resource", "connection", "name", "run", "arguments", "done_when", "failed_when", "goal").compact
    watch.steps[index] = watch.steps[index].to_h.merge(repaired)
    "Repaired step #{index + 1} of watch #{watch.id}. It now reads: #{read(watch.steps[index])}"
  end

  def extend_watch(given)
    watch = find_watch(given["watch"])
    return "There is no watch called #{given['watch']} in this chat." unless watch

    watch.minutes = given["minutes"]
    "Watch #{watch.id} now runs for #{watch.minutes} minutes from when it started."
  end

  def stop_watch(given)
    watch = find_watch(given["watch"])
    return "There is no watch called #{given['watch']} in this chat." unless watch

    @watches.delete(watch)
    "Stopped watch #{watch.id}, \"#{watch.title}\"."
  end

  def list_watches(_given)
    return "No watch is running in this chat." if @watches.empty?

    @watches.map { |watch| "Watch #{watch.id} \"#{watch.title}\": #{steps_of(watch)}" }.join("\n")
  end

  def make_plan(given)
    plan = Plan.new(id: "P#{@plans.size + 1}", goal: given["goal"].to_s, status: "going",
                    steps: Array(given["steps"]).map { |step| step.to_h.merge("status" => "waiting") })
    @plans << plan
    "Plan #{plan.id} saved for \"#{plan.goal}\". The person sees it as a checklist:\n#{plan_lines(plan)}"
  end

  def update_plan(given)
    plan = find_plan(given["plan"])
    return "There is no plan going in this chat." unless plan

    plan.steps = Array(given["revise"]).map { |step| step.to_h.merge("status" => "waiting") } if given["revise"].present?
    number = given["step"].to_i
    step = plan.steps[number - 1] if number.positive?
    step&.merge!(given.slice("status", "note", "verdict").compact)
    "Plan #{plan.id}:\n#{plan_lines(plan)}"
  end

  def finish_plan(given)
    plan = find_plan(given["plan"])
    return "There is no plan going in this chat." unless plan

    plan.status = "finished"
    plan.outcome = given["outcome"]
    "Plan #{plan.id} finished: #{plan.outcome}"
  end

  def cancel_plan(given)
    plan = find_plan(given["plan"])
    return "There is no plan going in this chat." unless plan

    plan.status = "cancelled"
    "Plan #{plan.id} cancelled: #{given['reason']}"
  end

  def steps_of(watch)
    watch.steps.each_with_index.map { |step, index| "step #{index + 1} \"#{step['label']}\" last read: #{read(step)}." }.join(" ")
  end

  # Reads a step the way the watch would, through the read it names, without using up any of the scenario's answers.
  def read(step)
    tool = step["capability"].presence || step["tool"].presence
    return NOTHING unless tool

    arguments = step.slice("resource", "connection", "name", "run").compact.merge(step["arguments"].to_h)
    found, = @case.answer_for(tool, arguments, @used.dup, @ran)
    found ? found.result.lines.first.to_s.strip.truncate(READ_SHOWN) : NOTHING
  end

  def find_watch(reference)
    return @watches.last if reference.blank?

    @watches.find { |watch| watch.id.casecmp?(reference.to_s) } ||
      @watches.find { |watch| watch.title.downcase.include?(reference.to_s.downcase) } ||
      (@watches.last if @watches.one?)
  end

  def step_index(watch, reference)
    number = reference.to_s[/\A\d+\z/]&.to_i
    return (number - 1).clamp(0, [ watch.steps.size - 1, 0 ].max) if number

    watch.steps.index { |step| step["label"].to_s.casecmp?(reference.to_s) } || 0
  end

  def find_plan(reference)
    going = @plans.select { |plan| plan.status == "going" }
    going.find { |plan| plan.id.casecmp?(reference.to_s) } || going.last
  end

  def plan_lines(plan)
    plan.steps.each_with_index.map { |step, index| "#{index + 1}. #{step['description']} (#{step['status']})#{" #{step['note']}" if step['note']}" }.join("\n")
  end
end
