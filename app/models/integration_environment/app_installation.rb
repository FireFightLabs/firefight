# What the provider last said of the app installation this row was made through (Integrations::Installations): whether
# it was removed, suspended or shares nothing (installation_state, nil while it works), and in installation_details the
# account it is on, the address of its settings at the provider and what it was granted, in the pack's own shape. None
# of it is a secret.
module IntegrationEnvironment::AppInstallation
  extend ActiveSupport::Concern

  DETAIL_ACCOUNT = "account".freeze
  DETAIL_PAGE = "page".freeze
  DETAIL_ACCESS = "access".freeze
  DETAIL_ACCESS_AT = "access_at".freeze

  # The ledger's action for removing the app from the account, the same a person needs to disconnect.
  UNINSTALL_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INTEGRATIONS, Ability::Action::ACTION_DELETE)
  UNINSTALL_LABEL = "Disconnect".freeze

  included do
    validates :installation_state, inclusion: { in: Integrations::Installations::STATES }, allow_nil: true
  end

  def installation_stopped? = installation_state.present?

  def installation_account = installation_details.to_h[DETAIL_ACCOUNT].presence

  def installation_page = installation_details.to_h[DETAIL_PAGE].presence

  def installation_access = installation_details.to_h[DETAIL_ACCESS]

  def installation_access_stale?(age)
    stamp = installation_details.to_h[DETAIL_ACCESS_AT]
    stamp.blank? || Time.iso8601(stamp) <= age.ago
  rescue ArgumentError
    true
  end

  # What the provider said of the installation now (Integrations::Installations::Installation), read while this row held
  # its state. What it left out, such as the account of one that is gone, stays as it was. A delivery that changed the
  # state while it was read wins, since it is newer than the read.
  def installation_checked!(found)
    details = { DETAIL_ACCOUNT => found.account, DETAIL_PAGE => found.page }.compact
    details = details.merge(DETAIL_ACCESS => found.access, DETAIL_ACCESS_AT => Time.current.utc.iso8601) if found.access
    merge_installation_details!(details)
    installation_marked!(found.state)
  end

  # What a minted token said the installation holds. One statement, so it never undoes a state written at the same time.
  def store_installation_access!(access)
    merge_installation_details!(DETAIL_ACCESS => access, DETAIL_ACCESS_AT => Time.current.utc.iso8601)
  end

  # The state the provider said, keeping when it was first seen while it stays the same. With from, only while the row is
  # still in that state, one statement, so a newer delivery is never undone by a read that started before it.
  def installation_marked!(state, from: installation_state)
    return if from == state

    moved = self.class.where(id: id, installation_state: from).update_all(installation_state: state, installation_state_at: state && Time.current, updated_at: Time.current)
    reload if moved.positive?
  end

  # Disconnecting forgets the installation, so nothing calls the provider as it again.
  def forget_installation!
    update!(base_config: base_config.to_h.except(IntegrationEnvironment::INSTALLATION_KEY), installation_details: {},
            installation_state: nil, installation_state_at: nil)
  end

  # Why Firefight may not remove the app from the account when this connection is disconnected, or nil.
  def uninstall_blocked_reason = Integrations::Installations.uninstall_blocked_reason(self)

  # Removes the app from the account at the provider as the person disconnecting, in the activity log under their name.
  # Answers why it could not, or nil once it is gone.
  def uninstall_app!(by:)
    AbilityGateway.authorize!(
      principal: by, action_key: UNINSTALL_ACTION_KEY, workspace: integration.workspace,
      params: { "app" => "uninstall", "connection" => integration.slug, "account" => installation_account }.compact,
      context: { source: AbilityGateway::SOURCE_WEB, triggered_by_label: UNINSTALL_LABEL }
    ) { Integrations::Installations.uninstall!(self) }
    nil
  rescue Integrations::Error, AbilityGateway::Denied, AbilityGateway::PendingApproval => error
    error.message
  end

  private

  def merge_installation_details!(details)
    self.class.where(id: id).update_all([ "installation_details = installation_details || ?::jsonb, updated_at = ?", details.to_json, Time.current ])
    self.installation_details = installation_details.to_h.merge(details)
    clear_attribute_change(:installation_details)
  end
end
