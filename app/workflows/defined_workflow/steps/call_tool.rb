# Calls any tool Halon can call, through the same tool a chat offers: a connected provider's, a capability such as
# resource_status or restart, a general read, or one of Firefight's own. It runs as whoever the run acts as, so grants,
# approval rules and the activity log decide it as they decide Halon's calls. A call an approval rule holds parks the
# step until someone decides, then reads how things stand again and runs exactly the call that was approved. A denial
# fails the step, which takes its error route when it has one.
class DefinedWorkflow::Steps::CallTool < DefinedWorkflow::Steps::Base
  kind "call_tool"
  label "Call a tool"
  group GROUP_TOOLS
  config_help "tool (any tool you can call, by its name), arguments (its arguments, values may be references), undo (for a change, how a person " \
              "puts it back, one sentence). Outputs answer and data (the answer read as JSON when it is)."

  KEY_TOOL = "tool".freeze
  KEY_ARGUMENTS = "arguments".freeze
  OUTPUT_ANSWER = "answer".freeze
  OUTPUT_DATA = "data".freeze
  ANSWER_LIMIT = 4_000
  # How long a held call waits for someone to decide, when the step sets no time limit of its own.
  APPROVAL_LIMIT = 24.hours
  CHECKPOINT_HELD = "held_approval".freeze
  APPROVAL = "approval".freeze

  class << self
    def changes?(config, workspace) = DefinedWorkflow::Reach.changes?(workspace, config[KEY_TOOL], config[KEY_ARGUMENTS])

    def checks?(config, workspace) = !changes?(config, workspace)

    def output_fields(_config) = [ OUTPUT_ANSWER, OUTPUT_DATA ]

    def problems(step, workspace)
      config = step["config"].to_h
      named = step["name"].presence || "A step"
      return [ "#{named} needs the tool it calls." ] if config[KEY_TOOL].to_s.strip.empty?
      return [ "#{named} calls #{config[KEY_TOOL]}, which is not a tool in this workspace." ] unless DefinedWorkflow::Reach.tool_known?(workspace, config[KEY_TOOL])
      return [ "#{named} gives its tool arguments as named values." ] unless config.fetch(KEY_ARGUMENTS, {}).is_a?(Hash)

      super
    end

    def reach(config, workspace) = DefinedWorkflow::Reach.for_tool(workspace, config[KEY_TOOL], config[KEY_ARGUMENTS])

    def describe(config, workspace)
      arguments = config[KEY_ARGUMENTS].to_h
      [ Chat::Tools.title_for(config[KEY_TOOL], workspace, arguments), (arguments.to_json if arguments.any?) ].compact.join(" ").truncate(200)
    end
  end

  def tool_name = @config[KEY_TOOL].to_s

  def arguments = @config[KEY_ARGUMENTS].to_h

  def perform
    return simulated_output(self.class.describe(@config, workspace)) if simulated?
    return call(nil) unless changes?

    parked = frozen
    return parked if parked

    held = @step.reload.checkpoint.to_h[CHECKPOINT_HELD]
    return after_decision(held) if held

    first = read_first(named, asked)
    return first if first.is_a?(SolidWorkflow::Park)

    call(nil)
  end

  private

  def named = Chat::Tools.label(tool_name, arguments, workspace: workspace).presence || tool_name

  def asked = arguments.map { |key, value| [ key, value.is_a?(String) ? value : value.to_json ] }

  def call(approval_id)
    agent_run = Workflow::AgentRun.new(run: @run, record: record, approval_id: approval_id)
    entry = Chat::Tools.catalog(agent_run).find { |found| found.name.to_s == tool_name }
    raise Refused, unavailable(entry) unless entry&.tool

    answer = entry.tool.call(**arguments.deep_symbolize_keys)
    return wait_for(agent_run.held) if agent_run.held
    raise Failed, (agent_run.raw.presence || answer).to_s.truncate(ANSWER_LIMIT) if agent_run.failed? || waiting?(entry)

    output_of(agent_run.raw.nil? ? answer.to_s : agent_run.raw.to_s)
  end

  def output_of(said) = { OUTPUT_ANSWER => said, OUTPUT_DATA => parsed(said) }

  def waiting?(entry) = entry.tool.respond_to?(:waiting?) && entry.tool.waiting?

  def unavailable(entry)
    return "There is no tool called #{tool_name} here, so the workflow needs updating or the tool switching on." unless entry
    return "#{tool_name} can change things, and this step only reads." if entry.state == Chat::Tools::STATE_READS_ONLY

    "#{@run.workflow.name} may not use #{tool_name}. An admin grants it on the workflow's page, under what it can do."
  end

  def parsed(text)
    value = JSON.parse(text.to_s)
    value.is_a?(Hash) || value.is_a?(Array) ? value : nil
  rescue JSON::ParserError
    nil
  end

  # The call waits for whoever an approval rule names. The step parks, and the decision is delivered to it.
  def wait_for(approval)
    approval.update!(workflow_run: @run) if approval.workflow_run_id.nil?
    ApprovalResumption.park_workflow_step!(approval, @step.id, @step.name)
    SolidWorkflow::Step.where(id: @step.id).update_all([ "checkpoint = COALESCE(checkpoint, '{}'::jsonb) || jsonb_build_object(?::text, ?::text)", CHECKPOINT_HELD, approval.id ])
    SolidWorkflow::Park.new(wake_at: approval_deadline)
  end

  def after_decision(approval_id)
    approval = Ability::Approval.find_by(id: approval_id)
    raise Refused, "The approval this call waited for is gone, so nothing ran." unless approval

    decided = @step.checkpoint.to_h.dig(CHECKPOINT_DELIVERED, "#{APPROVAL}:#{approval.id}")
    return undecided(approval) unless decided

    unless approval.approved?
      raise Refused, "#{approval.approver&.actor_display_name || 'An approver'} declined #{named}, so nothing ran."
    end

    again = read_first(named, asked, after: approval.id)
    return again if again.is_a?(SolidWorkflow::Park)

    call(approval.id)
  end

  def undecided(approval)
    return SolidWorkflow::Park.new(wake_at: approval_deadline) if approval_deadline > Time.current

    waited = ActiveSupport::Duration.build(approval_window).inspect
    if approval.pending? && approval.expire!(reason: "Nobody decided within #{waited}, so it did not run.").expired?
      ActiveRecord.after_all_transactions_commit { AbilityApprovalResolvedJob.perform_later(approval.id) }
    end
    raise Refused, "Nobody decided on #{named} within #{waited}, so it did not run."
  end

  def approval_window = (@step.timeout_seconds || APPROVAL_LIMIT.to_i).seconds.to_i

  def approval_deadline = (@step.first_started_at || Time.current) + approval_window.seconds
end
