# Writes the undo of an applied fix, from what each step actually did, and posts it in the run's thread with its own
# Apply fix. Halon writes it, a person applies it, so nothing is put back without a click.
class Investigation::UndoWriter
  WRITING = "Halon is writing the undo. It shows here when it is ready, to apply like any fix.".freeze
  # A refusal from the plan's own check, said as the reason the undo could not be written.
  COULD_NOT = "Halon could not write an undo for this fix".freeze
  NO_ANSWER = "#{COULD_NOT}, since the model could not be reached. Ask again in a moment, or check the model settings.".freeze
  BROKE = "#{COULD_NOT}, since something went wrong on Firefight's side. Ask again.".freeze

  def self.request!(plan, by:)
    blocked = plan.undo_blocked_reason
    return blocked if blocked
    return plan.reload.undo_blocked_reason || "#{COULD_NOT}." unless plan.request_undo!(by: by)

    InvestigationUndoJob.perform_later(plan.id)
    nil
  end

  def initialize(plan)
    @plan = plan
  end

  def write!
    workspace = @plan.finding.investigation.workspace
    steps = @plan.steps.map do |step|
      FirefightAi::UndoWriter::Step.new(position: step.position, kind: step.kind, description: step.description, repository: step.repository,
                                        tool: step.tool_name, arguments: step.arguments.presence, result: step.result, undo: step.undo, status: step.status)
    end
    tools = Integration::Tool.in_workspace(workspace).reject(&:read_only).map(&:model_facing_name)
    fix = FirefightAi::UndoWriter.new(workspace).write(steps, summary: @plan.summary, tools: tools, inferable: @plan.finding.investigation)
    undo = @plan.propose_undo!(fix)
    publish(undo)
  rescue Investigation::RemediationPlan::Refused => refused
    @plan.undo_failed!("#{COULD_NOT}. #{refused.message}")
  rescue FirefightAi::OutOfCredit
    @plan.undo_failed!(AiCredit.cannot(@plan.finding.investigation.workspace, "write the undo for this fix"))
  rescue FirefightAi::Error => error
    Rails.logger.warn({ event: "fix.undo_not_written", plan_id: @plan.id, error: error.class.name }.to_json)
    @plan.undo_failed!(NO_ANSWER)
  rescue StandardError => error
    Rails.logger.warn({ event: "fix.undo_broke", plan_id: @plan.id, error: error.class.name }.to_json)
    @plan.undo_failed!(BROKE)
  end

  private

  def publish(undo)
    investigation = @plan.finding.investigation
    return if investigation.thread_id.blank?

    adapter = WorkspaceAdapter.for(investigation.workspace)
    adapter.post_undo_plan(channel_id: investigation.channel_id, thread_id: investigation.thread_id, plan: undo)
    # The fix's own message loses its Undo fix, now there is one.
    if @plan.progress_message_id
      adapter.update_fix_progress(channel_id: @plan.progress_channel_id, message_id: @plan.progress_message_id, plan: @plan.reload)
    end
  rescue AdapterError => error
    Rails.logger.warn({ event: "fix.undo_not_posted", plan_id: @plan.id, error: error.class.name }.to_json)
  end
end
