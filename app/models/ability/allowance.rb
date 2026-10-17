module Ability
  # One entry of what Halon may do without asking, in any person's chat with it. It is a risky change an admin chose,
  # through a capability such as rollback or through one connection's tool, kept to a connection or an environment when
  # one is named, such as "Roll back deploys in Staging". It stands in for the chat person's yes, as Allow for the rest of this
  # chat does for one chat, and never for an approval rule, a grant, or a person's say on who may do what. A change that
  # reaches access or a secret, a statement that writes rows, a general tool and a tool on a remote server are never on
  # it, since Firefight cannot keep each of those to what the entry says. Investigations act under unattended rules
  # instead (Ability::UnattendedRule), and an outside agent's chat over MCP asks as before.
  class Allowance < ApplicationRecord
    self.table_name = "ability_allowances"

    # Set only by a person in Firefight, never with a token, like unattended rules.
    TOKEN_CHANGE_REFUSAL = "What Halon may do without asking is set only by a person in Firefight, never with a token.".freeze

    def self.change_blocked_reason(source) = (TOKEN_CHANGE_REFUSAL if AbilityGateway::TOKEN_SOURCES.include?(source))

    CAPABILITIES = [ Integrations::Capabilities::ROLLBACK, Integrations::Capabilities::RESTART, Integrations::Capabilities::SCALE ].freeze
    # How an entry reads, as a person says it: "Roll back deploys in Staging".
    CAPABILITY_WORDS = {
      Integrations::Capabilities::ROLLBACK => "Roll back deploys",
      Integrations::Capabilities::RESTART => "Restart services and databases",
      Integrations::Capabilities::SCALE => "Scale services"
    }.freeze

    belongs_to :workspace
    belongs_to :action, class_name: "Ability::Action", optional: true
    belongs_to :integration, optional: true
    belongs_to :environment, class_name: "CatalogEntry", optional: true
    belongs_to :created_by, class_name: "WorkspaceMembership", optional: true
    has_many :invocations, class_name: "Ability::Invocation", foreign_key: :allowance_id, inverse_of: :allowance, dependent: :nullify

    validates :capability, inclusion: { in: CAPABILITIES }, allow_nil: true
    validate :one_change
    validate :action_allowed
    validate :scope_in_workspace
    validates :capability, uniqueness: { scope: %i[workspace_id action_id integration_id environment_id], message: "is already on the list there" }

    scope :enabled, -> { where(enabled: true) }

    # How many changes Halon made under each entry, in one subquery rather than a count per row.
    def self.with_usage_counts
      select("#{table_name}.*",
             "(SELECT COUNT(*) FROM ability_invocations WHERE ability_invocations.allowance_id = #{table_name}.id " \
             "AND ability_invocations.decision = '#{Ability::Invocation::DECISION_ALLOW}') AS usage_count")
    end

    def usage_count = has_attribute?(:usage_count) ? self[:usage_count].to_i : invocations.where(decision: Ability::Invocation::DECISION_ALLOW).count

    # The enabled entry that lets Halon make this call without asking, or nil. action is the tool's action the call runs
    # as. capability is the capability Halon called, when it called one, and integration the connection it routed to.
    def self.covering(workspace, action:, environment_id:, capability: nil, integration_id: nil)
      return nil unless action&.tool?

      entries = workspace.allowances.enabled.where(environment_id: [ nil, environment_id ].uniq)
      by_tool = entries.where(action_id: action.id)
      by_capability = (entries.where(capability: capability, integration_id: [ nil, integration_id ].uniq) if capability)
      [ by_tool, by_capability ].compact.reduce(:or).order(:created_at).first unless refusal_for(action)
    end

    # Why a tool's change can never be on the list, or nil.
    def self.refusal_for(action)
      return "Only a change through a connection's tool or a capability can be on this list." unless action&.tool?
      return "#{tool_words(action)} only reads, so Halon never asks before it." if action.read?

      tool = action.source
      return "#{tool_words(action)} is no longer connected." unless tool.is_a?(Integration::Tool)
      return "#{tool_words(action)} changes who can reach something or a secret, so a person is always asked." if Integrations::SafeChanges.access?(tool)
      return "#{tool_words(action)} runs on a server Firefight cannot see inside, so it cannot tell what a call changes." unless tool.integration.native?
      return "#{tool_words(action)} reaches a whole API, so what one call changes is known only when it is made." if Integrations::ReadGuards.for(tool)
      return "#{tool_words(action)} writes rows, which are counted and shown to the person before each write." if action.effect?(Ability::Action::EFFECT_DATA_WRITE)

      nil
    end

    def self.tool_words(action)
      tool = action.source
      return action.key unless tool.is_a?(Integration::Tool)

      "#{tool.name.to_s.tr('_', ' ').humanize} on #{tool.integration.display_name}"
    end

    # The entry as a person reads it, which is also how it is named wherever Halon acted under it.
    def sentence
      what = capability ? CAPABILITY_WORDS.fetch(capability) : self.class.tool_words(action)
      [ what, (" on #{integration.display_name}" if capability && integration), (" in #{environment.name}" if environment) ].join
    end

    def delete_blocked_reason
      return if usage_count.zero?

      "Halon made #{usage_count} #{'change'.pluralize(usage_count)} under this, so it stays for the record. Turn it off instead."
    end

    CHANGEABLE = %i[capability action_key integration environment enabled].freeze

    # What the dashboard, the API or MCP asks to change. A tool is named by its key, a connection by its slug and an
    # environment by its id or name, each found in this workspace only. Absent keys keep what the entry has.
    def self.changes_from(workspace, given)
      given = given.to_h.symbolize_keys
      changes = {}
      changes[:enabled] = given[:enabled] if given.key?(:enabled)
      changes[:capability] = given[:capability].presence if given.key?(:capability)
      changes[:action] = tool_action(workspace, given[:action_key]) if given.key?(:action_key)
      changes[:integration] = connection(workspace, given[:integration]) if given.key?(:integration)
      changes[:environment] = environment_named(workspace, given[:environment]) if given.key?(:environment)
      changes
    end

    def self.tool_action(workspace, key)
      key.blank? ? nil : Ability::Action.find_by(workspace: workspace, key: key.to_s, kind: Ability::Action::KIND_TOOL)
    end

    def self.connection(workspace, slug) = slug.blank? ? nil : workspace.integrations.find_by(slug: slug.to_s)

    def self.environment_named(workspace, reference)
      return nil if reference.blank?

      workspace.environment_entries.find_by(id: reference.to_s) || workspace.environment_entries.find_by("lower(catalog_entries.name) = ?", reference.to_s.downcase)
    end

    # What an entry can name, a capability some connection here can make, with the connections that make it, and each
    # connection's tool that may be on the list. value is what the dashboard sends back, label how a person reads it.
    Choice = Data.define(:value, :label, :connections) do
      def initialize(connections: [], **) = super
    end

    def self.capability_choices(workspace, tools: workspace.switched_on_tools)
      Integrations::Capabilities.offered(workspace, tools: tools).filter_map do |spec, able|
        next unless CAPABILITIES.include?(spec.key)

        connections = able.map(&:integration).uniq.sort_by(&:display_name).map { |integration| Choice.new(value: integration.slug, label: integration.display_name) }
        Choice.new(value: spec.key, label: CAPABILITY_WORDS.fetch(spec.key), connections: connections)
      end
    end

    def self.tool_choices(workspace, tools: workspace.switched_on_tools)
      changes = tools.reject(&:read_only?)
      actions = Ability::Action.where(workspace: workspace, key: changes.map(&:action_key)).includes(:source).to_a
      actions.reject { |action| refusal_for(action) }.map { |action| Choice.new(value: action.key, label: tool_words(action)) }.sort_by(&:label)
    end

    # How the API and MCP read an entry back, in the same words the screen shows.
    def payload
      {
        id: id, capability: capability, action_key: action&.key, integration: integration&.slug, environment: environment && { id: environment.id, name: environment.name },
        enabled: enabled, sentence: sentence, created_by: created_by&.display_name, times_used: usage_count, delete_blocked_reason: delete_blocked_reason,
        created_at: created_at.utc.iso8601, updated_at: updated_at.utc.iso8601
      }
    end

    private

    def one_change
      errors.add(:base, "Choose a capability or one connection's tool.") if capability.nil? == action_id.nil?
      errors.add(:integration, "only narrows a capability, since a tool already belongs to one connection") if action_id && integration_id
    end

    def action_allowed
      return unless action

      refusal = self.class.refusal_for(action)
      errors.add(:base, refusal) if refusal
      errors.add(:action, "must belong to this workspace") if action.workspace_id != workspace_id
    end

    def scope_in_workspace
      errors.add(:integration, "must be a connection in this workspace") if integration && integration.workspace_id != workspace_id
      errors.add(:environment, "must be one of this workspace's environments") if environment && !workspace.environment_entries.exists?(id: environment.id)
    end
  end
end
