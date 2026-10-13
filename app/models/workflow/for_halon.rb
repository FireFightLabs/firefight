# What Halon reads of a workflow before it proposes a change: the version a person sees on the canvas, the suggestions
# still waiting on them, and every kind of step it may add with the settings each takes. Ids are what a change names,
# names are what a person reads and what later steps refer to as {{steps.<name>.<field>}}.
module Workflow::ForHalon
  extend ActiveSupport::Concern

  def for_halon(facts: Workflow::StepKinds::Facts.new(workspace: workspace))
    shown = shown_version
    {
      "workflow" => { "id" => id, "name" => name, "slug" => slug, "description" => description.presence, "on" => enabled? }.compact,
      "version" => halon_version_line(shown),
      "trigger" => shown.trigger,
      "steps" => shown.steps,
      "edges" => shown.edges,
      "outputs" => shown.outputs,
      "waiting_suggestions" => proposals.map { |edit| { "id" => edit.id, "change" => edit.sentence, "reason" => edit.reason } },
      "step_kinds" => Workflow::StepKinds.offered.map { |kind| halon_kind(kind, facts) },
      "tools" => facts.tools.map { |tool| { "name" => tool.name, "description" => tool.description, "changes_something" => !tool.read_only } }.presence
    }.compact
  end

  private

  def halon_version_line(shown)
    return "Nothing is saved yet. The first change starts a draft." unless shown.persisted?
    return "The open draft, revision #{shown.revision}. Changes land here once a person accepts them." if shown.draft?

    "The live version #{shown.number}. A change accepted here opens a draft from it."
  end

  def halon_kind(kind, facts)
    {
      "kind" => kind.key, "label" => kind.label, "description" => kind.description,
      "settings" => kind.fields_for(facts).map { |field| { "key" => field.key, "kind" => field.kind, "required" => field.required, "description" => field.description, "options" => field.options.presence }.compact },
      "defaults" => kind.defaults,
      "outputs" => kind.outputs.call({ "kind" => kind.key, "config" => kind.defaults }, facts)
    }
  end
end
