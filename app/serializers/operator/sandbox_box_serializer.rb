module Operator
  # A code sandbox as its provider and the app know it. Its address and key are never sent.
  class SandboxBoxSerializer < BaseSerializer
    object_as :box

    PHASE_UNION = ProviderSandbox::PHASES.map(&:inspect).join(" | ")
    FLAG_UNION = Operator::Sandboxes::FLAGS.map(&:inspect).join(" | ")
    ORIGIN_UNION = Operator::Sandboxes::ORIGINS.map(&:inspect).join(" | ")

    type :string
    def key = box.key

    type :string
    def provider = box.provider

    type :string
    def provider_name = SandboxProviders.name_of(box.provider)

    type :string
    def ref = box.ref

    type :string, optional: true
    def name = box.name

    type :string, optional: true
    def size = box.size

    type PHASE_UNION, optional: true
    def phase = box.phase

    # The provider's own word for its state.
    type :string, optional: true
    def state = box.state

    type :string, optional: true
    def started_at = box.started_at&.utc&.iso8601

    type :string, optional: true
    def ended_at = box.ended_at&.utc&.iso8601

    type :string, optional: true
    def last_used_at = box.last_used_at&.utc&.iso8601

    type :string, optional: true
    def workspace_id = box.workspace&.id

    type :string, optional: true
    def workspace_name = box.workspace&.name

    type "{ kind: #{ORIGIN_UNION}; label: string; href: string | null } | null"
    def origin
      return unless box.origin

      { kind: box.origin.kind, label: box.origin.label, href: origin_href(box.origin) }
    end

    type :number
    def seconds = box.seconds

    # nil when its provider puts no price on it, or the app holds no record of it.
    type :number, optional: true
    def cost_micros = box.cost_micros

    type "(#{FLAG_UNION})[]"
    def flags = box.flags

    type :boolean
    def recorded = box.recorded

    type :boolean
    def held = box.held

    private

    def origin_href(origin)
      routes = Rails.application.routes.url_helpers
      case origin.kind
      when Operator::Sandboxes::ORIGIN_INVESTIGATION then routes.operator_halon_run_path(origin.id)
      when Operator::Sandboxes::ORIGIN_CHAT then routes.operator_halon_chat_path(origin.id)
      when Operator::Sandboxes::ORIGIN_CODE_FIX then routes.operator_workspace_path(origin.id)
      end
    end
  end
end
