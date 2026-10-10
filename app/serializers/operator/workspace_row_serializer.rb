module Operator
  # A workspace for the console list, with where its code boxes run and their spend in the window.
  class WorkspaceRowSerializer < BaseSerializer
    object_as :row

    type :string
    def id = row.workspace.id

    type :string
    def name = row.workspace.name

    type :string
    def created_at = row.workspace.created_at.utc.iso8601

    # The provider it is held to, or the deployment's own order.
    type :string
    def placement = WorkspaceSandbox.placement_label(row.workspace.sandbox_provider)

    type :boolean
    def held = row.workspace.sandbox_provider.present?

    type :number
    def boxes = row.boxes

    type :number
    def failovers = row.failovers

    type :number
    def sandbox_micros = row.sandbox_micros
  end
end
