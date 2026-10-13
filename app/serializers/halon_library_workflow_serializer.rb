# One of Firefight's library workflows as the library page lists it: what it does, its version, what starts it, the
# workspace's workflows already made from it, and why it cannot be used here yet.
class HalonLibraryWorkflowSerializer < BaseSerializer
  object_as :item

  type :string
  def key = item.key

  type :string
  def name = item.name

  type :string
  def description = item.description

  type :number
  def version = item.version

  type "'#{Workflow::Trigger::KINDS.join("' | '")}'"
  def trigger_kind = item.trigger.to_h[Workflow::Trigger::KEY_KIND]

  type :number
  def step_count = Workflow::Version.all_steps(item.definition["steps"]).size

  type "string[]"
  def used_by = options.fetch(:used, {}).fetch(item.key, [])

  # What using it asks first: each question its trigger asks without a default, which every run needs an answer to.
  type "{ key: string; question: string }[]"
  def questions = Workflow::Trigger.inputs(item.trigger).select { |input| input["default"].blank? }.map { |input| input.slice("key", "question") }

  type :string, optional: true
  def use_blocked_reason = Workflow.from_library_blocked_reason(item, options.fetch(:workspace))
end
