# Which issue tracker an incident's items are kept in step with, and when a new item gets an issue there. An admin
# chooses a connection to a tracker under Settings, Workspace, named by its slug, which never changes, and where new
# issues go (Integrations::Issues target fields, such as a Linear team or a Jira project). Changes made in the tracker
# reach Firefight through the tracker's webhook, sent to an address only this workspace has and checked with the signing
# secret the admin pastes from the tracker. Only items linked to the chosen connection's issues are kept in step.
module Workspace::IssueSync
  extend ActiveSupport::Concern

  ISSUE_CREATION_NEVER = "never".freeze
  ISSUE_CREATION_ASKED = "asked".freeze
  ISSUE_CREATION_FOLLOW_UPS = "follow_ups".freeze
  ISSUE_CREATION_ALL = "all".freeze

  Choice = Data.define(:value, :label)

  ISSUE_CREATION_CHOICES = [
    Choice.new(value: ISSUE_CREATION_NEVER, label: "Never"),
    Choice.new(value: ISSUE_CREATION_ASKED, label: "Only when someone asks"),
    Choice.new(value: ISSUE_CREATION_FOLLOW_UPS, label: "Always for follow-ups"),
    Choice.new(value: ISSUE_CREATION_ALL, label: "Always for actions and follow-ups")
  ].freeze
  ISSUE_CREATIONS = ISSUE_CREATION_CHOICES.map(&:value).freeze

  included do
    encrypts :issue_webhook_secret

    normalizes :issue_tracker, with: ->(value) { value.to_s.strip.presence }
    normalizes :issue_webhook_secret, with: ->(value) { value.to_s.strip.presence }
    normalizes :issue_tracker_target, with: ->(value) { value.to_h.transform_values { |field| field.to_s.strip }.compact_blank }

    validates :issue_creation, inclusion: { in: ISSUE_CREATIONS }
    validate :issue_tracker_is_a_tracker
    validate :issue_tracker_chosen_to_create
    # A secret is for the tracker it was copied from, so choosing another one asks for its own.
    before_save :forget_issue_webhook_secret, if: -> { will_save_change_to_issue_tracker? && !will_save_change_to_issue_webhook_secret? }
    before_save :give_issue_webhook_address, if: -> { issue_tracker.present? && issue_webhook_token.blank? }
    # Where issues go is the chosen tracker's, so choosing another asks again.
    before_save :forget_issue_tracker_target, if: -> { will_save_change_to_issue_tracker? && !will_save_change_to_issue_tracker_target? }
  end

  # The chosen connection, removed or not, or nil while none is chosen.
  def issue_tracker_connection
    return if issue_tracker.blank?

    integrations.find_by(slug: issue_tracker, provider: issue_tracker_providers)
  end

  # The chosen connection while items can be kept in step with its issues.
  def issue_sync_connection
    integration = issue_tracker_connection
    integration if integration&.operational?
  end

  def issue_creation_never? = issue_creation == ISSUE_CREATION_NEVER

  # Whether a new item of this kind gets an issue without anyone asking.
  def creates_issue_for?(action_type)
    issue_creation == ISSUE_CREATION_ALL ||
      (issue_creation == ISSUE_CREATION_FOLLOW_UPS && action_type == IncidentAction::ACTION_TYPE_FOLLOWUP)
  end

  # Why Firefight cannot open issues in the chosen tracker, or nil when it can or none is chosen.
  def issue_creation_blocked_reason
    return if issue_tracker.blank?

    integration = issue_tracker_connection
    return "The issue tracker chosen for incident items was removed, so no issues are opened or kept in step. Choose another one." if integration.nil? || integration.deleted_at
    return "#{integration.name} is switched off, so no issues are opened or kept in step until it is switched on again." if integration.disabled_at

    tool = Integrations::Issues.create_tool(integration.provider)
    return "#{integration.name}'s #{tool} tool is switched off, so no issues are opened. Switch it on under Integrations." unless issue_tool_on?(integration, tool)

    missing = Integrations::Issues.target_fields(integration.provider).find { |field| field.required && issue_tracker_target[field.key].blank? }
    "Say which #{missing.label.downcase} new issues go to." if missing
  end

  # Why changes made in the tracker do not reach Firefight, or nil when they do or no tracker is chosen.
  def issue_webhook_blocked_reason
    integration = issue_sync_connection
    return if integration.nil?

    "Changes made in #{integration.name} do not reach Firefight until its webhook's signing secret is saved here." if issue_webhook_secret.blank?
  end

  # A tracker the settings page offers, with where its new issues go (Integrations::Issues::TargetField) and how to
  # send its webhook to Firefight, as the tracker documents it.
  TrackerChoice = Data.define(:value, :label, :fields, :steps)

  # What the settings page offers: no tracker, then every connection to a tracker that keeps items in step.
  def issue_tracker_choices
    trackers = integrations.where(deleted_at: nil, provider: issue_tracker_providers).order(:name)
    none = TrackerChoice.new(value: nil, label: "None", fields: [], steps: [])
    [ none ] + trackers.map do |integration|
      TrackerChoice.new(value: integration.slug, label: issue_tracker_label(integration),
                        fields: Integrations::Issues.target_fields(integration.provider), steps: Integrations::Issues.setup_steps(integration.provider))
    end
  end

  def issue_webhook_secret_set? = issue_webhook_secret.present?

  private

  def issue_tracker_providers = IntegrationProvider.all.map(&:key).select { |key| Integrations::Issues.syncs?(key) }

  def issue_tool_on?(integration, tool) = integration.tools.enabled.available.exists?(name: tool)

  def issue_tracker_label(integration)
    provider = IntegrationProvider.find(integration.provider).name
    integration.name == provider ? provider : "#{integration.name} (#{provider})"
  end

  def forget_issue_webhook_secret
    self.issue_webhook_secret = nil
  end

  def forget_issue_tracker_target
    self.issue_tracker_target = {}
  end

  def give_issue_webhook_address
    self.issue_webhook_token = SecureRandom.base58(32)
  end

  def issue_tracker_is_a_tracker
    return if issue_tracker.blank? || !will_save_change_to_issue_tracker?
    return if integrations.where(deleted_at: nil, slug: issue_tracker, provider: issue_tracker_providers).exists?

    errors.add(:issue_tracker, "is not an issue tracker connected to this workspace")
  end

  def issue_tracker_chosen_to_create
    return if issue_creation_never? || issue_tracker.present?

    errors.add(:issue_creation, "needs an issue tracker to open issues in")
  end
end
