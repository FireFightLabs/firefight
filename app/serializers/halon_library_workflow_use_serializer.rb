# One of the workspace's workflows as the library page lists it: whether it came from Firefight's library and follows it
# or is the workspace's own copy, the library version it holds, whether it is live, and what changed in a newer version a
# copy has not taken.
class HalonLibraryWorkflowUseSerializer < BaseSerializer
  object_as :workflow

  type :string
  def id = workflow.id

  type :string
  def name = workflow.name

  type :boolean
  def from_library = workflow.from_library?

  # The library item it came from, or nil for one of the workspace's own or one Firefight no longer ships.
  type :string, optional: true
  def item_name = workflow.library_item&.name

  type :boolean
  def following = workflow.following_library?

  type :number, optional: true
  def library_version = workflow.library_version

  # It has a published version that runs, rather than only a draft.
  type :boolean
  def published = workflow.live_version_id.present?

  type "{ version: number; changes: { kind: '#{Workflow::Changes::KIND_ADDED}' | '#{Workflow::Changes::KIND_REMOVED}' | '#{Workflow::Changes::KIND_CHANGED}'; text: string }[] } | null"
  def library_update
    item = workflow.library_update
    return unless item

    changes = Workflow::Changes.between(workflow.library_base, item.definition)
    { version: item.version, changes: changes.map { |change| { kind: change.kind, text: change.text } } }
  end
end
