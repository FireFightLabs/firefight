module Operator
  # A code fix, with what its sandbox cost beside what its model calls cost.
  class SandboxFixSerializer < BaseSerializer
    object_as :fix

    type :string
    def id = fix.id

    type :string
    def repository = fix.repository

    type :string
    def at = fix.at.utc.iso8601

    type :number
    def ai_micros = fix.ai_micros

    # nil when none of its boxes had a price, such as Docker on the deployment's own machines.
    type :number, optional: true
    def sandbox_micros = fix.sandbox_micros

    type :number
    def sandbox_seconds = fix.sandbox_seconds

    type "string[]"
    def providers = fix.providers

    type :string, optional: true
    def pull_request_url = fix.pull_request_url
  end
end
