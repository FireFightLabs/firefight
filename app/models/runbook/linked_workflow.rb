# A runbook is a guide and what it runs lives in the one workflow it links. Every step stays on the
# runbook as a checklist item, so incidents and the actions claimed from its steps read as before.
module Runbook::LinkedWorkflow
  extend ActiveSupport::Concern

  class Refused < StandardError; end

  TAKEN_NAME_SUFFIX = "runbook".freeze

  included do
    belongs_to :workflow, optional: true
    validate :workflow_in_workspace
  end

  class_methods do
    # Run once for every workspace by the migrations that moved runbooks into workflows.
    def move_runnable_parts!(workspace)
      workspace.runbooks.includes(:runbook_steps).order(:position).filter_map(&:move_runnable_parts!)
    end

    def names_a_run?(given)
      given = given.to_h.symbolize_keys
      given.key?(:inputs) || given.key?(:watch) || Array(given[:steps]).any? { |step| step.to_h.with_indifferent_access[:tool].present? }
    end
  end

  def runnable_parts? = runbook_steps.any?(&:tool?) || inputs.any? || watch.present?

  def own_parts
    steps = runbook_steps.select(&:tool?).map { |step| { "title" => step.title, "tool" => step.tool, "arguments" => step.arguments } }
    Runbook::WorkflowShape::Parts.new(steps: steps, inputs: inputs.map { |input| input.slice(*Runbook::Procedure::INPUT_FIELDS) }, watch: watch)
  end

  # A workflow changed on its page beyond what a runbook can say still answers the inputs a run asks.
  def readable_parts
    return Runbook::WorkflowShape::Parts.new unless workflow

    version = workflow.live_version || workflow.draft
    Runbook::WorkflowShape.parts_of(version) || Runbook::WorkflowShape::Parts.new(inputs: Workflow::Trigger.inputs(version&.trigger))
  end

  def workflow_for_agents
    return unless workflow

    version = workflow.live_version || workflow.draft
    parts = Runbook::WorkflowShape.parts_of(version)
    steps = parts ? parts.steps : Workflow::Listing.summary(workflow)[:steps]
    { name: workflow.name, slug: workflow.slug, state: workflow.state, page: Workflow::Links.page(workflow), steps: steps }
  end

  def runnable_now? = workflow.present? && workflow.start_blocked_reason.nil?

  def run_blocked_reason(member)
    return "#{name} links no workflow to run." unless workflow

    workflow.run_now_blocked_reason(member)
  end

  # The link is claimed on a runbook still linking none, so two moves at once make one workflow. A workflow never keeps a
  # value shaped like a secret, so a runbook holding one is left as it was.
  def move_runnable_parts!
    return unless runnable_parts?

    transaction(requires_new: true) do
      made = write_new_workflow!(own_parts, author_kind: Workflow::AUTHOR_FIREFIGHT, by: nil,
                                            reason: "Moved from the #{name} runbook, which keeps its steps as a checklist.")
      raise ActiveRecord::Rollback unless self.class.where(id: id, workflow_id: nil).update_all(workflow_id: made.id, updated_at: Time.current) == 1

      reload
      clear_runnable_parts!
      made
    end
  rescue ActiveRecord::RecordInvalid => invalid
    Rails.logger.warn({ event: "runbook.move_refused", runbook_id: id, reason: invalid.record.errors.full_messages.to_sentence }.to_json)
    nil
  end

  # Each of steps, inputs and watch is replaced only when given. A workflow changed on its page beyond what a runbook can
  # say is never written over.
  def write_runnable_parts!(given, by:)
    current = workflow ? Runbook::WorkflowShape.parts_of(workflow.draft || workflow.live_version) : Runbook::WorkflowShape::Parts.new
    raise Refused, "#{workflow.name} was changed on its page beyond steps that call a tool and a watch, so change what it runs there." if current.nil?

    wanted = Runbook::WorkflowShape::Parts.new(
      steps: given.key?(:steps) ? given[:steps] : current.steps,
      inputs: given.key?(:inputs) ? given[:inputs] : current.inputs,
      watch: given.key?(:watch) ? given[:watch] : current.watch
    )
    return if wanted == current

    reason = "Written as the #{name} runbook's steps."
    if workflow
      rewrite_draft!(wanted, by: by, reason: reason)
    else
      update!(workflow: write_new_workflow!(wanted, author_kind: Workflow::AUTHOR_PERSON, by: by, reason: reason))
    end
    workflow
  end

  private

  def write_new_workflow!(parts, author_kind:, by:, reason:)
    made = Workflow.create!(workspace: workspace, name: free_workflow_name, description: summary.presence, created_by: by,
                            aliases: aliases.reject { |other| Workflow.named(workspace.workflows, other) })
    made.versions.create!(number: 1, status: Workflow::Version::STATUS_DRAFT, author_kind: author_kind, author: by, reason: reason,
                          **Runbook::WorkflowShape.content(parts).symbolize_keys)
    made
  end

  # Guarded on the revision the draft was opened at, so an edit made on its page in between is never written over.
  def rewrite_draft!(parts, by:, reason:)
    draft = workflow.open_draft!(by: by, reason: reason)
    ids = Workflow::Version.all_steps(draft.steps).to_h { |step| [ step["name"], step["id"] ] }
    content = Runbook::WorkflowShape.content(parts, ids: ids)
    problem = Workflow::Version.content_problem(content)
    raise Refused, problem if problem

    moved = Workflow::Version.where(id: draft.id, status: Workflow::Version::STATUS_DRAFT, revision: draft.revision)
                             .update_all(**content.slice(*Workflow::Version::CONTENT).symbolize_keys, revision: draft.revision + 1, updated_at: Time.current)
    raise Refused, "Someone changed #{workflow.name}'s draft at the same time, so look again." unless moved == 1
  end

  def clear_runnable_parts!
    runbook_steps.select(&:tool?).each { |step| step.update!(tool: nil, arguments: {}) }
    update!(inputs: [], watch: nil)
    runbook_steps.reset
  end

  def free_workflow_name
    own = name.first(Workflow::NAME_LIMIT - TAKEN_NAME_SUFFIX.length - 4).strip
    taken = ->(candidate) { Workflow.named(workspace.workflows, candidate) || workspace.workflows.exists?(slug: Sluggable.word_slug(candidate)) }
    return own unless taken.call(own)

    base = "#{own} #{TAKEN_NAME_SUFFIX}"
    (1..).lazy.map { |number| number == 1 ? base : "#{base} #{number}" }.find { |candidate| !taken.call(candidate) }
  end

  def workflow_in_workspace
    errors.add(:workflow, "must belong to this workspace") if workflow && workflow.workspace_id != workspace_id
  end
end
