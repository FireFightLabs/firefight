module Operator
  # A box that started on the backup provider because the one before it could not start it.
  class SandboxFailoverSerializer < BaseSerializer
    object_as :failover

    type :string
    def id = failover.id

    type :string
    def at = failover.at.utc.iso8601

    type :string
    def from = failover.from

    type :string
    def to = failover.to

    type :string
    def reason = failover.reason
  end
end
