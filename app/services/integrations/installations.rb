module Integrations
  # An app a person installs on their account at a provider, which a connection is made through instead of credentials
  # (NativePack.install_url), such as a GitHub App. The installation can change at the provider without Firefight: an
  # owner removes or suspends the app, takes everything away from it, or grants it more. This is the one way the rest of
  # the app asks about that, and it never names a provider.
  #
  # A pack whose provider gates access behind an app answers on its class side:
  #   installation(row)            what the provider says of the installation now, an Installation, read with the app's own
  #                                credentials, with state REMOVED once the provider no longer knows it
  #   uninstall(row)               removes the app from the account, raising Integrations::Error when the provider refuses
  #   forget_access(row)           drops what the pack cached to call as the installation, such as a minted token, so the
  #                                next call gets one holding what the installation was granted now
  #   missing_access(row, tool)    what the tool needs that the installation was not granted, as names a person finds in
  #                                the app's settings (["Actions read"]), empty when nothing is missing or nothing is known
  #   app_name                     what the provider calls the app, such as "GitHub App"
  #   reach_name                   what an installation shares with the app, such as "repositories"
  module Installations
    SUSPENDED = "suspended".freeze
    REMOVED = "removed".freeze
    # The account shares nothing with the app, such as every repository taken away from a GitHub App.
    EMPTIED = "emptied".freeze
    STATES = [ SUSPENDED, REMOVED, EMPTIED ].freeze

    # What an app wide delivery says changed about an installation (MapEventSource installation_change).
    CHANGE_REMOVED = "removed".freeze
    CHANGE_SUSPENDED = "suspended".freeze
    CHANGE_RESTORED = "restored".freeze
    # It was granted something new, so a token minted before lacks it.
    CHANGE_ACCESS = "access".freeze
    # What it shares changed, which may have left it nothing.
    CHANGE_REACH = "reach".freeze

    # What the provider says of one installation. state is nil while it works, account the name a person knows it by,
    # page the address of its settings at the provider, and access what it was granted, in the pack's own shape.
    Installation = Data.define(:state, :account, :page, :access) do
      def initialize(state: nil, account: nil, page: nil, access: nil) = super
    end

    # What disconnecting did with one installation: whether the app was removed from the account, if that failed why, and
    # if another connection still uses it, the reason it stays.
    Disconnected = Data.define(:account, :provider, :page, :removed, :error, :shared) do
      def words
        return "Firefight's app was removed from #{account} on #{provider}." if removed
        return Sentence.join("Firefight could not remove its app from #{account} on #{provider}", error, after: "Remove it there.") if error
        return shared if shared

        "Firefight's app is still installed on #{account}. Remove it on #{provider} if you no longer need it."
      end

      # Where the person removes it themselves, nil once it is gone or while another connection needs it.
      def link = removed || shared || page.blank? ? nil : { label: "Open #{account} on #{provider}", url: page }
    end

    # A stored access older than this is read again before a tool is refused for it, so a grant made on the provider's
    # side is seen before Firefight says it is missing.
    RECHECK_AFTER = 1.minute

    # The ledger's action for removing the app from the account, the same a person needs to disconnect.
    UNINSTALL_ACTION_KEY = Ability::Action.system_key(Ability::Action::RESOURCE_INTEGRATIONS, Ability::Action::ACTION_DELETE)
    UNINSTALL_LABEL = "Disconnect".freeze

    module_function

    def pack_of(provider_key)
      pack = NativePack.for(provider_key)
      pack if pack.respond_to?(:installation)
    end

    # Whether the connection was made through an app the provider can say something about.
    def installed?(row) = row.installation_id.present? && pack_of(row.integration.provider).present?

    def provider_name(row) = ResourceMap.provider_name(row.integration.provider)

    # Every connection made through one installation of a provider's app, in any workspace, removed or not at the provider,
    # so a change there reaches each.
    def rows_for(provider_key, installation)
      return IntegrationEnvironment.none if installation.blank?

      IntegrationEnvironment.joins(:integration).where(integrations: { provider: provider_key.to_s, deleted_at: nil })
                            .where("integration_environments.base_config ->> :key = :installation", key: IntegrationEnvironment::INSTALLATION_KEY,
                                                                                                    installation: installation.to_s)
    end

    # Reads the installation at the provider and keeps what it said on the row.
    def check!(row)
      return unless installed?(row)

      was = row.installation_state
      row.installation_checked!(pack_of(row.integration.provider).installation(row))
      restored!(row) if was && row.installation_state.nil?
    end

    # What the connection reaches is read again once it works again, since changes were not followed meanwhile.
    def restored!(row) = MapSweepJob.perform_later(row)

    # A verified app wide delivery, applied to every connection made through the installation it names. A removal or a
    # suspension is taken as said, since the provider signed it. Anything else is read again from the provider.
    def delivered!(provider_key, source, payload, headers:)
      return unless source.respond_to?(:installation_change)

      change = source.installation_change(payload, headers: headers)
      return unless change

      rows_for(provider_key, source.installation_of(payload, headers: headers)).find_each { |row| changed!(row, change) }
    end

    def changed!(row, change)
      pack = pack_of(row.integration.provider)
      return unless pack

      pack.forget_access(row) unless change == CHANGE_REACH
      case change
      when CHANGE_REMOVED then row.installation_marked!(REMOVED)
      when CHANGE_SUSPENDED then row.installation_marked!(SUSPENDED)
      when CHANGE_RESTORED
        stopped = row.installation_stopped?
        row.installation_marked!(nil)
        restored!(row) if stopped
        InstallationCheckJob.perform_later(row)
      else InstallationCheckJob.perform_later(row)
      end
    end

    # Why the connection cannot be used while the installation is in this state, or nil while it works.
    def stopped_reason(row)
      return unless row.installation_stopped?

      provider = provider_name(row)
      account = row.installation_account || "the account"
      case row.installation_state
      when REMOVED
        "Firefight's app was removed from #{account} on #{provider}, so #{row.integration.name}'s tools stop and its changes no longer reach the map. " \
          "Reconnect to install it again."
      when SUSPENDED
        "Firefight's app is suspended on #{account} on #{provider}, so #{row.integration.name}'s tools stop until an owner unsuspends it there."
      else
        "#{account} shares no #{reach_name(row)} with Firefight's app on #{provider}, so #{row.integration.name}'s tools have nothing to read. " \
          "Choose what it may reach on #{provider}."
      end
    end

    # Why the provider's changes do not reach the map, said beside live updates. The connection says the rest.
    def live_updates_reason(row)
      provider = provider_name(row)
      account = row.installation_account || "the account"
      case row.installation_state
      when REMOVED then "Firefight's app was removed from #{account} on #{provider}, so changes there do not reach the map."
      when SUSPENDED then "Firefight's app is suspended on #{account} on #{provider}, so changes there do not reach the map."
      when EMPTIED then "#{account} shares no #{reach_name(row)} with Firefight's app on #{provider}, so no changes reach the map."
      end
    end

    # How a connection's installation state reads as a label, such as "Removed on GitHub".
    def state_label(row)
      provider = provider_name(row)
      case row.installation_state
      when REMOVED then "Removed on #{provider}"
      when SUSPENDED then "Suspended on #{provider}"
      when EMPTIED then "No #{reach_name(row)} on #{provider}"
      end
    end

    def reach_name(row) = pack_of(row.integration.provider)&.reach_name || "resources"

    def app_name(row) = pack_of(row.integration.provider)&.app_name || "#{provider_name(row)} app"

    # What the tool needs on this row that the installation was not granted, as last stored. Nothing is read from the
    # provider, so a page or a listing can ask.
    def missing(row, tool_name)
      return [] unless row && installed?(row) && !row.installation_stopped?

      pack_of(row.integration.provider).missing_access(row, tool_name)
    end

    # The same, but a grant stored a while ago is read again first, so a permission an owner just accepted is not refused.
    def missing_now(row, tool_name)
      lacking = missing(row, tool_name)
      return lacking if lacking.empty? || !row.installation_access_stale?(RECHECK_AFTER)

      check!(row)
      missing(row, tool_name)
    rescue Integrations::Error
      lacking
    end

    # A person reads this beside the tool: "Needs Actions read in the GitHub App."
    def missing_words(row, lacking) = "Needs #{lacking.to_sentence} in the #{app_name(row)}."

    # What a tool (Integration::Tool) on this row answers instead of calling the provider, or nil when it may call.
    def refusal(row, tool)
      return unless row && installed?(row)

      tool_name = tool.model_facing_name
      stopped = stopped_reason(row)
      return "#{tool_name} was not run. #{stopped} Tell the person." if stopped

      lacking = missing_now(row, tool.remote_name)
      return if lacking.empty?

      where = row.installation_page ? " at #{row.installation_page}" : ""
      "#{tool_name} was not run. It needs #{lacking.to_sentence} in the #{app_name(row)}, which #{row.installation_account || 'the account'} has not " \
        "granted. An owner grants it in the app's settings on #{provider_name(row)}#{where}. Tell the person rather than guessing."
    end

    # Raised in place of reading a connection whose installation is stopped, so a sweep says why and keeps the map.
    def stopped!(row)
      reason = row && installed?(row) && stopped_reason(row)
      raise Integrations::Error, reason if reason
    end

    # Why Firefight may not remove the app from the account when this row's connection is disconnected, or nil.
    # Another connection made through the same installation, in this workspace or any other, still needs it.
    def uninstall_blocked_reason(row)
      return "#{row.integration.name} was not connected through an app." unless installed?(row)
      return "Firefight's app is already gone from #{provider_name(row)}." if row.installation_state == REMOVED

      others = rows_for(row.integration.provider, row.installation_id).where.not(integration_id: row.integration_id).includes(:integration).to_a
      return if others.empty?

      here = others.find { |other| other.integration.workspace_id == row.integration.workspace_id }
      return "#{here.integration.name} also uses this installation, so the app stays on #{provider_name(row)}." if here

      "A connection in another Firefight workspace uses this installation, so the app stays on #{provider_name(row)}."
    end

    # Disconnects every installation the connection was made through. The app is removed from each account in
    # uninstall (installation ids) that no other connection uses, recorded in the activity log as the person's, and
    # Firefight forgets every installation and what it cached either way. Answers one Disconnected for each.
    def disconnected!(integration, uninstall:, by:)
      rows = integration.integration_environments.select { |row| installed?(row) }
      chosen = Array(uninstall).map(&:to_s)
      done = rows.group_by(&:installation_id).filter_map do |installation_id, same|
        row = same.first
        next if row.installation_state == REMOVED

        shared = uninstall_blocked_reason(row)
        error = uninstall_as(row, by: by) if chosen.include?(installation_id) && shared.nil?
        removed = chosen.include?(installation_id) && shared.nil? && error.nil?
        Disconnected.new(account: row.installation_account || "the account", provider: provider_name(row), page: row.installation_page,
                         removed: removed, error: error, shared: shared)
      end
      rows.each { |row| forget!(row) }
      done
    end

    # Removes the app from the account at the provider as the person disconnecting, in the activity log under their name.
    # Answers why it could not, or nil once it is gone.
    def uninstall_as(row, by:)
      Chat::ToolCall.run!(
        principal: by, action_key: UNINSTALL_ACTION_KEY, workspace: row.integration.workspace,
        params: { "app" => "uninstall", "connection" => row.integration.slug, "account" => row.installation_account }.compact,
        context: { source: AbilityGateway::SOURCE_WEB, triggered_by_label: UNINSTALL_LABEL }
      ) { pack_of(row.integration.provider).uninstall(row) }
      nil
    rescue Integrations::Error, AbilityGateway::Denied, AbilityGateway::PendingApproval => error
      error.message
    end

    # Firefight forgets the installation and what it cached for it, so nothing calls the provider as it again.
    def forget!(row)
      pack_of(row.integration.provider)&.forget_access(row)
      row.forget_installation!
    end

    # A connection made through an installation again, starting from what the provider says of it now.
    def connected!(row, installation_id)
      pack_of(row.integration.provider)&.forget_access(row)
      row.store_installation!(installation_id)
    end
  end
end
