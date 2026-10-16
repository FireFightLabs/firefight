module Operator
  # One time a platform call failed, with the incident whose channel it was in.
  class PlatformFailureSerializer < BaseSerializer
    Row = Data.define(:failure, :incident)

    object_as :row

    type :string
    def id = row.failure.id

    type :string
    def at = row.failure.created_at.utc.iso8601

    type :string
    def workspace = row.failure.workspace.name

    type :string, optional: true
    def channel = row.failure.channel_id

    type :string, optional: true
    def channel_name = row.incident&.channel_name

    type :string, optional: true
    def incident = row.incident&.identifier

    type :string, optional: true
    def incident_id = row.incident&.id

    type :string
    def error_class = row.failure.error_class

    type :string, optional: true
    def message = row.failure.message
  end
end
