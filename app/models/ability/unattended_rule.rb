module Ability
  # A change a team lets Halon make on its own, decided ahead: roll back or restart one resource on the map once a metric
  # read fresh is above a threshold. It never grants anything. Halon still needs a grant of the tool, and the rule only
  # stands in for the approval an approval rule would ask for, which the gateway checks (AbilityGateway.approval_gate!).
  # Only a fix Halon proposed in a run an alert started is ever applied under one.
  class UnattendedRule < ApplicationRecord
    self.table_name = "ability_unattended_rules"

    CAPABILITIES = [ Integrations::Capabilities::ROLLBACK, Integrations::Capabilities::RESTART ].freeze
    CAPABILITY_VERBS = {
      Integrations::Capabilities::ROLLBACK => "Roll back",
      Integrations::Capabilities::RESTART => "Restart"
    }.freeze
    METRICS = Integrations::Capabilities::METRIC_NAMES
    # How each metric reads in a sentence, such as "the average of its 5xx responses".
    METRIC_LABELS = {
      "cpu" => "CPU", "memory" => "memory", "requests" => "requests", "errors" => "errors", "http_4xx" => "4xx responses",
      "http_5xx" => "5xx responses", "cpu_time" => "CPU time", "network_in" => "network in", "network_out" => "network out",
      "tcp_connections" => "TCP connections", "disk" => "disk", "bandwidth" => "bandwidth", "latency_p95" => "p95 latency",
      "invocations" => "invocations", "duration" => "duration", "throttles" => "throttles"
    }.freeze
    DEFAULT_MINUTES = 10
    # What a new rule reads until someone picks another.
    DEFAULT_METRIC = "errors".freeze
    ROUTING_ONLY = "routing-only".freeze
    MAX_MINUTES = 24 * 60

    belongs_to :workspace
    belongs_to :resource, class_name: "ResourceMap::Resource"
    belongs_to :created_by, class_name: "WorkspaceMembership", optional: true
    has_many :applied_steps, class_name: "Investigation::RemediationStep", foreign_key: :applied_under_rule_id,
                             inverse_of: :applied_under_rule, dependent: :nullify

    validates :capability, inclusion: { in: CAPABILITIES }
    validates :metric, inclusion: { in: METRICS }
    validates :threshold, numericality: { greater_than_or_equal_to: 0 }
    validates :minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_MINUTES }
    validate :resource_in_workspace

    scope :enabled, -> { where(enabled: true) }

    # How many changes Halon made under each rule, in one subquery rather than a count per row.
    def self.with_usage_counts
      select("#{table_name}.*",
             "(SELECT COUNT(*) FROM investigation_remediation_steps WHERE investigation_remediation_steps.applied_under_rule_id = " \
             "#{table_name}.id) AS usage_count")
    end

    def usage_count = has_attribute?(:usage_count) ? self[:usage_count].to_i : applied_steps.count

    def spec = Integrations::Capabilities.spec(capability)

    # The rule as a person reads it, which is also how it is named wherever it acted.
    def sentence
      "#{CAPABILITY_VERBS.fetch(capability)} #{resource.name} when the average of its #{metric_label} over the last #{minutes} minutes is above #{shown_threshold}."
    end

    def metric_label = METRIC_LABELS.fetch(metric, metric)

    def shown_threshold = threshold.to_d.to_s("F").sub(/\.0\z/, "")

    # Why the rule cannot act now, or nil. The rule stays as it was set, and the screen says what is missing.
    def blocked_reason
      return "#{resource.name} is no longer on the resource map, so this rule cannot act." if resource.removed_at
      return "#{investigator_name} holds no grant of #{call.tool.integration.name}'s #{call.tool.name}, so this rule cannot act yet. Grant it under Gateway, Permissions." unless granted?

      nil
    rescue Integrations::Capabilities::Unroutable => error
      "No connection can #{CAPABILITY_VERBS.fetch(capability).downcase} #{resource.name} now (#{error.message.delete_suffix('.')}), so this rule cannot act."
    end

    def delete_blocked_reason
      return if usage_count.zero?

      "Halon acted under this rule #{usage_count} #{'time'.pluralize(usage_count)}, so it stays for the record. Turn it off instead."
    end

    # The provider tool the rule's change runs through now, routed the way any rollback or restart is. A rollback is
    # routed with a stand in for what it goes back to, since only the tool is wanted here and nothing is sent.
    def call = @call ||= Integrations::Capabilities.resolve_for(resource, capability, spec.required.index_with { ROUTING_ONLY })

    # Whether a fix's step is the change this rule allows. A step names a resource only when it was written as a
    # capability, which routed it to the provider call it holds, so the capability and the resource settle it.
    def covers?(step)
      step.action? && step.tool_name == spec.tool_name && step.resource_id == resource_id
    end

    # The gateway's question when a call made under this rule meets an approval rule: whether it is a step Halon is making
    # under this rule now, in a fix it is applying, with exactly these arguments.
    def admits?(principal:, action_key:, scope:, params:)
      return false unless enabled? && principal == SystemAgent.investigator

      running = applied_steps.joins(:plan).where(investigation_remediation_plans: { status: Investigation::RemediationPlan::STATUS_APPLYING })
                             .where(status: Investigation::RemediationStep::STATUS_RUNNING, action_key: action_key)
      running.any? { |step| covers?(step) && step.call_scope == scope.to_h.stringify_keys && step.call_arguments == params.to_h.stringify_keys }
    rescue Integration::UnknownEnvironment
      false
    end

    # A fresh reading of the rule's metric, as Halon, through the gateway. Never a remembered one.
    def read!(incident: nil) = Ability::UnattendedRule::Reading.new(self, incident: incident).read!

    # A resource a rule can name, with the changes some connection holding it can make.
    ResourceChoice = Data.define(:resource, :capabilities)

    def self.resource_choices(workspace)
      able = CAPABILITIES.to_h { |key| [ key, Integrations::Capabilities.actionable(workspace, key).index_by(&:id) ] }
      resources = able.values.flat_map(&:values).uniq(&:id).sort_by { |resource| resource.name.downcase }
      resources.map { |resource| ResourceChoice.new(resource: resource, capabilities: CAPABILITIES.select { |key| able[key].key?(resource.id) }) }
    end

    CHANGEABLE = %i[capability metric threshold minutes enabled].freeze

    # What the dashboard, the API or MCP asks to change. The resource is found on this workspace's map by its id there,
    # its name or its provider's id, so a rule can never name another workspace's. Absent keys keep what the rule has.
    def self.changes_from(workspace, given)
      given = given.to_h.symbolize_keys
      changes = given.slice(*CHANGEABLE)
      reference = given[:resource_id] || given[:resource]
      reference.nil? ? changes : changes.merge(resource: resource_named(workspace, reference.to_s))
    end

    def self.resource_named(workspace, reference)
      present = ResourceMap::Resource.present.where(workspace_id: workspace.id)
      by_name = present.where("lower(name) = ?", reference.downcase).limit(2).to_a
      present.find_by(id: reference) || (by_name.first if by_name.one?) || present.find_by(external_id: reference)
    end

    # How the API and MCP read a rule back, in the same words the screen shows.
    def payload
      {
        id: id, capability: capability, resource: { id: resource_id, name: resource.name }, metric: metric, threshold: threshold.to_f,
        minutes: minutes, enabled: enabled, sentence: sentence, created_by: created_by&.display_name, times_acted: usage_count,
        blocked_reason: blocked_reason, delete_blocked_reason: delete_blocked_reason,
        created_at: created_at.utc.iso8601, updated_at: updated_at.utc.iso8601
      }
    end

    # The change in a few words, which names the rule in a notice: "roll back checkout".
    def change_words = "#{CAPABILITY_VERBS.fetch(capability).downcase} #{resource.name}"

    # The enabled rule that lets Halon make a step's change on its own, or nil.
    def self.covering(workspace, step) = workspace.unattended_rules.enabled.includes(:resource).find { |rule| rule.covers?(step) }

    def investigator_name = SystemAgent.investigator.actor_display_name

    private

    def granted?
      Ability::Resolver.resolve(SystemAgent.investigator, workspace).covers?(call.tool.action_key, call.scope)
    end

    def resource_in_workspace
      errors.add(:resource, "must be on this workspace's resource map") if resource && resource.workspace_id != workspace_id
    end
  end
end
