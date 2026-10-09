# Which issue tracker an incident's items are kept in step with, and when a new item gets an issue there. An admin
# chooses a connection to a tracker under Settings, Workspace, named by its slug, which never changes, and where new
# issues go (Integrations::Issues target fields, such as a Linear team or a Jira project). Changes made in the tracker
# reach Firefight through the tracker's webhook, sent to an address only this workspace has and checked with the signing
# secret the admin pastes from the tracker, which the tracker connection's own row keeps (IntegrationEnvironment::
# IssueWebhook). Only items linked to the chosen connection's issues are kept in step.
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
    normalizes :issue_tracker, with: ->(value) { value.to_s.strip.presence }
    normalizes :issue_tracker_target, with: ->(value) { value.to_h.transform_values { |field| field.to_s.strip }.compact_blank }

    validates :issue_creation, inclusion: { in: ISSUE_CREATIONS }
    validate :issue_tracker_is_a_tracker
    validate :issue_tracker_chosen_to_create
    # A secret is for the tracker it was copied from, so choosing another one asks for its own.
    after_save :forget_previous_issue_webhook, if: :saved_change_to_issue_tracker?
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

  # The row a tracker connection is called through, which keeps its webhook, or nil while there is none.
  def issue_webhook_row(integration = issue_tracker_connection) = integration&.resolve_environment(nil)

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

    reason = issue_sync_tools_blocked_reason(integration)
    return reason if reason

    missing = Integrations::Issues.target_fields(integration.provider).find { |field| field.required && issue_tracker_target[field.key].blank? }
    "Say which #{missing.label.downcase} new issues go to." if missing
  end

  # Why changes made in the tracker do not reach Firefight, or nil when they do or no tracker is chosen. A webhook
  # Firefight registered itself needs no secret pasted.
  def issue_webhook_blocked_reason
    integration = issue_sync_connection
    return if integration.nil?

    row = issue_webhook_row(integration)
    return "#{integration.name} has no environment to call, so changes made there do not reach Firefight." if row.nil?
    return Integrations::Sentence.join("Firefight could not register #{integration.name}'s webhook, so changes made there do not reach it", row.issue_webhook_error) if row.issue_webhook_error.present?
    return if row.issue_webhook_registered?

    "Changes made in #{integration.name} do not reach Firefight until its webhook's signing secret is saved here." unless row.issue_webhook_secret_set?
  end

  def issue_webhook_registered? = issue_webhook_row&.issue_webhook_registered? || false

  # Each tool keeping items in step must be on, and Firefight's issue sync must hold it, since every call is made as
  # that agent. nil when they all are.
  def issue_sync_tools_blocked_reason(integration = issue_sync_connection)
    return if integration.nil?

    tools = integration.tools.available.where(name: Integrations::Issues.sync_tools(integration.provider)).index_by(&:name)
    missing = Integrations::Issues.sync_tools(integration.provider) - tools.keys
    return "#{integration.name} offers no #{missing.to_sentence}, so items cannot be kept in step with it. Refresh its tools under Integrations." if missing.any?

    off = tools.values.reject(&:enabled?).map(&:name)
    return "#{integration.name}'s #{off.to_sentence} #{off.one? ? 'is' : 'are'} switched off, so items are not kept in step. Choose the tracker again to switch #{off.one? ? 'it' : 'them'} back on." if off.any?

    held = Ability::Resolver.resolve(SystemAgent.issue_sync, self)
    lost = tools.values.map(&:action_key).reject { |key| held.covers?(key) }
    return if lost.empty?

    "Firefight issue sync no longer holds #{lost.to_sentence}, so items are not kept in step. Choose the tracker again to grant #{lost.one? ? 'it' : 'them'} back."
  end

  # Switches on the tools keeping items in step calls and grants exactly those to Firefight's issue sync, through the
  # same grants the Permissions screen writes, so it opens and changes issues whoever made the item.
  def grant_issue_sync!(integration)
    agent = SystemAgent.issue_sync
    integration.tools.available.where(name: Integrations::Issues.sync_tools(integration.provider)).find_each do |tool|
      tool.update!(enabled: true) unless tool.enabled?
      Ability::Grant.grant!(workspace: self, principal: agent, target: { action: tool.ability_action || tool.sync_ability_action! })
    end
  end

  # Takes back what grant_issue_sync! granted. The tools stay as they are, since people may use them too.
  def revoke_issue_sync!(integration)
    keys = integration.tools.where(name: Integrations::Issues.sync_tools(integration.provider)).map(&:action_key)
    actions = Ability::Action.where(workspace_id: id, key: keys)
    ability_grants.where(principal: SystemAgent.issue_sync, action: actions).destroy_all
  end

  WEBHOOK_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_WORKSPACE, Ability::Action::ACTION_UPDATE)

  # Registering or removing the tracker's webhook reaches another system as part of changing these settings, so it is
  # authorized and ledgered as whoever changed them, and runs inside the block.
  def authorize_issue_webhook!(integration, by:, change:, &)
    AbilityGateway.authorize!(
      principal: by, action_key: WEBHOOK_ACTION_KEY, workspace: self, params: { "webhook" => change, "connection" => integration.slug },
      context: { source: AbilityGateway::SOURCE_ISSUE_SYNC, triggered_by_label: "Issue tracking settings" }, &
    )
  end

  def issue_webhook_registered!(webhook) = issue_webhook_row&.issue_webhook_registered!(webhook)

  def issue_webhook_failed!(words) = issue_webhook_row&.issue_webhook_failed!(words)

  # The secret an admin pasted from a tracker set up by hand, kept on the chosen tracker's row.
  def save_issue_webhook_secret!(secret)
    row = issue_webhook_row
    if row.nil?
      connection = issue_tracker_connection
      errors.add(:issue_webhook_secret, connection ? "cannot be saved until #{connection.name} has an environment to call" : "needs an issue tracker to sign for")
      raise ActiveRecord::RecordInvalid, self
    end

    row.update!(issue_webhook_secret: secret)
  end

  # A tracker the settings page offers, with where its new issues go (Integrations::Issues::TargetField) and how to
  # send its webhook to Firefight, as the tracker documents it.
  TrackerChoice = Data.define(:value, :label, :fields, :steps)

  # What the settings page offers, no tracker first and then every connection to a tracker that keeps items in step.
  def issue_tracker_choices
    trackers = integrations.where(deleted_at: nil, provider: issue_tracker_providers).order(:name)
    none = TrackerChoice.new(value: nil, label: "None", fields: [], steps: [])
    [ none ] + trackers.map do |integration|
      TrackerChoice.new(value: integration.slug, label: issue_tracker_label(integration),
                        fields: Integrations::Issues.target_fields(integration.provider), steps: Integrations::Issues.setup_steps(integration.provider))
    end
  end

  def issue_webhook_secret_set? = issue_webhook_row&.issue_webhook_secret_set? || false

  private

  def issue_tracker_providers = IntegrationProvider.all.map(&:key).select { |key| Integrations::Issues.syncs?(key) }

  def issue_tracker_label(integration)
    provider = IntegrationProvider.find(integration.provider).name
    integration.name == provider ? provider : "#{integration.name} (#{provider})"
  end

  def forget_previous_issue_webhook
    previous = issue_tracker_before_last_save
    return if previous.blank?

    issue_webhook_row(integrations.find_by(slug: previous, provider: issue_tracker_providers))&.forget_issue_webhook!
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
