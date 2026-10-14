# The workspace's workflows as an agent reads them, Halon in a chat and an outside agent over MCP alike: name and other
# names, what starts it, how it stands, when it runs next, its most runs an hour and how many it skipped in the last week,
# how it last went, its steps and the inputs a run asks.
module Workflow::Listing
  module_function

  def for(workspace)
    workflows = workspace.workflows.with_run_counts.includes(:live_version, :draft_version, :latest_run).ordered.to_a
    skipped = Workflow::SkippedRun.where(workflow_id: workflows.map(&:id), hour: Workflow::SkippedRun::SHOWN_FOR.ago..).group(:workflow_id).sum(:count)
    workflows.map { |workflow| summary(workflow, skipped: skipped.fetch(workflow.id, 0)) }
  end

  def summary(workflow, skipped: workflow.recent_skips.sum(&:count))
    version = workflow.live_version || workflow.draft_version
    kinds = version&.step_kinds || {}
    {
      name: workflow.name, slug: workflow.slug, aliases: workflow.aliases, description: workflow.description, state: workflow.state,
      starts: workflow.trigger_words, next_run_at: workflow.next_run_at&.iso8601, runs: workflow.run_count, runs_per_hour: workflow.runs_per_hour,
      skipped_runs_last_week: skipped,
      last_run: workflow.latest_run && { status: workflow.latest_run.status, at: (workflow.latest_run.finished_at || workflow.latest_run.created_at).iso8601,
                                         error: workflow.latest_run.error }.compact,
      inputs: Workflow::Trigger.inputs(version&.trigger).map { |input| input.slice("key", "question", "default", Workflow::Trigger::KEY_PRIVATE).compact },
      steps: Workflow::Version.all_steps(version&.steps).map { |step| "#{step['name']} (#{kinds[step['id']]&.label || step['kind']})" },
      page: Workflow::Links.page(workflow)
    }.compact
  end
end
