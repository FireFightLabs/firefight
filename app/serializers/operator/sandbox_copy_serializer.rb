module Operator
  # A kept copy, a provider's snapshot or an archive in the app's storage, with the prepared repository it holds.
  class SandboxCopySerializer < BaseSerializer
    object_as :copy

    FLAG_UNION = Operator::Sandboxes::FLAGS.map(&:inspect).join(" | ")

    type :string
    def key = copy.key

    type :string
    def provider = copy.provider

    type :string
    def provider_name = copy.provider == PreparedCopy::KEPT_IN_ARCHIVE ? "Firefight's storage" : SandboxProviders.name_of(copy.provider)

    type :string
    def ref = copy.ref

    type "#{ProviderSandbox::PURPOSE_IMAGE.inspect} | #{ProviderSandbox::PURPOSE_PREPARED.inspect} | #{ProviderSandbox::PURPOSE_RUN.inspect}"
    def purpose = copy.purpose

    type :string, optional: true
    def phase = copy.phase

    type :string, optional: true
    def state = copy.state

    type :string, optional: true
    def workspace_name = copy.workspace&.name

    type :string, optional: true
    def repository = copy.repository

    type :string, optional: true
    def created_at = copy.created_at&.utc&.iso8601

    type :string, optional: true
    def last_used_at = copy.last_used_at&.utc&.iso8601

    type :number, optional: true
    def byte_size = copy.byte_size

    type :number
    def monthly_micros = copy.monthly_micros

    type "(#{FLAG_UNION})[]"
    def flags = copy.flags
  end
end
