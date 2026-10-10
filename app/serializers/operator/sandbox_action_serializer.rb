module Operator
  # What an operator did to a sandbox, and who.
  class SandboxActionSerializer < BaseSerializer
    object_as :action

    type :string
    def id = action.id

    type "#{Operator::SandboxAction::ACTIONS.map(&:inspect).join(' | ')}"
    def action_name = action.action

    type :string
    def provider_name = SandboxProviders.name_of(action.provider)

    type :string
    def ref = action.ref

    type :string
    def operator = action.operator

    type :string, optional: true
    def outcome = action.outcome

    type :string
    def at = action.created_at.utc.iso8601
  end
end
