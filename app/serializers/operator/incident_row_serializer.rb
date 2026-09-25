module Operator
  # An incident for the console list, across all workspaces, with its count of failed records.
  class IncidentRowSerializer < BaseSerializer
    object_as :row

    type :string
    def id = row.incident.id

    type :string
    def identifier = row.incident.identifier

    type :string
    def name = row.incident.name

    type :string
    def workspace_name = row.incident.workspace.name

    type :string
    def status = row.incident.incident_status.name

    type :string, optional: true
    def declared_at = row.incident.declared_at&.utc&.iso8601

    type :number
    def problems = row.problems.to_i
  end
end
