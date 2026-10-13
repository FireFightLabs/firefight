# The workspace's workflows as an agent reads them, Halon in a chat and an outside agent over MCP alike: name and other
# names, what starts it, how it stands, when it runs next, how it last went, its steps and the inputs a run asks.
module Workflow::Listing
  module_function

  def for(workspace)
    workspace.workflows.with_run_counts.includes(:live_version, :draft_version, :latest_run).ordered.map { |workflow| summary(workflow) }
  end

  def summary(workflow)
    version = workflow.live_version || workflow.draft_version
    kinds = version&.step_kinds || {}
    {
      name: workflow.name, slug: workflow.slug, aliases: workflow.aliases, description: workflow.description, state: workflow.state,
      starts: workflow.trigger_words, next_run_at: workflow.next_run_at&.iso8601, runs: workflow.run_count,
      last_run: workflow.latest_run && { status: workflow.latest_run.status, at: (workflow.latest_run.finished_at || workflow.latest_run.created_at).iso8601,
                                         error: workflow.latest_run.error }.compact,
      inputs: Workflow::Trigger.inputs(version&.trigger).map { |input| input.slice("key", "question", "default", Workflow::Trigger::KEY_PRIVATE).compact },
      steps: Workflow::Version.all_steps(version&.steps).map { |step| "#{step['name']} (#{kinds[step['id']]&.label || step['kind']})" },
      page: Workflow::Links.page(workflow)
    }.compact
  end
end
