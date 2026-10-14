# One step as the canvas draws it: its name and title, its kind with the registry's words and icon, its settings as
# stored, the for each it sits inside, whether it reads or changes, the routes an edge out of it can carry, the fields
# it hands on, whether the workflow's own identity needs a grant to run it, and whether Halon last changed it.
class WorkflowStepNodeSerializer < BaseSerializer
  object_as :placed

  type :string
  def id
    step["id"].to_s
  end

  type :string
  def name
    step["name"].to_s
  end

  type :string
  def title
    Workflow::Edit.title_of(step["name"])
  end

  type :string
  def kind
    step["kind"].to_s
  end

  type :string
  def kind_label
    kind_spec&.label || kind.tr("_", " ").upcase_first
  end

  type "#{Workflow::StepKinds::ICONS.map(&:inspect).join(' | ')}"
  def icon
    kind_spec&.icon || Workflow::StepKinds::ICON_TOOL
  end

  type "#{Workflow::StepKinds::GROUPS.map(&:inspect).join(' | ')}"
  def group
    kind_spec&.group || Workflow::StepKinds::GROUP_TOOLS
  end

  type "#{Workflow::StepKinds::EDITORS.map(&:inspect).join(' | ')}"
  def editor
    kind_spec&.editor || Workflow::StepKinds::EDITOR_FIELDS
  end

  # A kind nothing in this Firefight runs, such as one from a newer version, is shown and kept but cannot be published.
  type :boolean
  def runnable
    Workflow::StepKinds.runnable?(kind)
  end

  type "Record<string, unknown>"
  def config
    step["config"].to_h
  end

  type "{ x: number; y: number }", optional: true
  def position
    position = step["position"]
    position.is_a?(Hash) && position["x"].is_a?(Numeric) && position["y"].is_a?(Numeric) ? { x: position["x"], y: position["y"] } : nil
  end

  type :number, optional: true
  def timeout_seconds
    step["timeout_seconds"]
  end

  type "{ max_attempts?: number; backoff?: #{DefinedWorkflow::BACKOFFS.map(&:inspect).join(' | ')}; backoff_seconds?: number }", optional: true
  def retry_settings
    step["retry"]
  end

  type "#{DefinedWorkflow::ON_FAILURE.map(&:inspect).join(' | ')}", optional: true
  def on_failure
    step["on_failure"]
  end

  type :string, optional: true
  def within
    placed.within
  end

  type "#{Workflow::StepKinds::EFFECTS.map(&:inspect).join(' | ')}"
  def effect
    Workflow::StepKinds.effect_of(step, facts)
  end

  type "string[]"
  def routes
    Workflow::StepKinds.routes_of(step)
  end

  # The words a route reads as where they are not its own, such as the label of an Ask a person choice for its key.
  type "Record<string, string>"
  def route_labels
    Workflow::StepKinds.route_labels_of(step)
  end

  # It waits on a person for as long as its settings say, so the time limit of its errors and retries has no say.
  type :boolean
  def waits
    Workflow::StepKinds.waits?(step)
  end

  type "string[]"
  def outputs
    Workflow::StepKinds.outputs_of(step, facts)
  end

  type :string, optional: true
  def grant_needed
    options[:workflow]&.grant_needed_for(Workflow::StepKinds.reach_of(step, facts))
  end

  # The output pinned for it on the draft, which test runs use in its place.
  type "{ output: Record<string, unknown>; route: string | null; pinnedAt: string | null }", optional: true
  def pin
    pin = options[:pins].to_h[step["id"]]
    return unless pin.is_a?(Hash)

    { output: pin[Workflow::Version::Pins::KEY_OUTPUT].to_h, route: pin[Workflow::Version::Pins::KEY_ROUTE], pinnedAt: pin[Workflow::Version::Pins::KEY_PINNED_AT] }
  end

  type :boolean
  def changed_by_halon
    options[:last_changes].to_h[step["id"]]&.by_halon? || false
  end

  private

  def step = placed.step

  def kind_spec = Workflow::StepKinds.find(kind)

  def facts = options[:facts] || Workflow::StepKinds::Facts.new
end
