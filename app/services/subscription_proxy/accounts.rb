module SubscriptionProxy
  # A workspace's subscription accounts as the proxy holds them: what each serves and how much of its limit is left, the
  # order the proxy tries them in, switching one off and on, and removing one. Every call names only this workspace's
  # credentials.
  class Accounts
    # The Codex limits, each a window with how much of it is used and when it resets.
    LIMIT_WINDOWS = %w[primary secondary].freeze
    # A finished sign-in no workspace claimed, left by a sign-in that broke off before Firefight heard it finish.
    UNCLAIMED_AFTER = 30.minutes

    # Sign-ins nobody finished are kept a day, so a page left open can still say what became of one.
    SIGN_INS_KEPT_FOR = 1.day

    # Every workspace's subscription accounts brought up to date from one read of the proxy's credentials.
    def self.sync_all!
      return unless SubscriptionProxy.usable?

      credentials = Client.new.credentials
      sweep_unclaimed!(credentials)
      SubscriptionSignIn.where(updated_at: ...SIGN_INS_KEPT_FOR.ago).delete_all
      Workspace.where(id: WorkspaceAiAccount.subscriptions.where.not(proxy_credential: nil).select(:workspace_id)).find_each do |workspace|
        new(workspace).sync!(credentials)
      rescue SubscriptionProxy::Error => error
        Rails.logger.warn({ event: "subscription_proxy.sync_failed", workspace_id: workspace.id, error: error.message }.to_json)
      end
    end

    def initialize(workspace)
      @workspace = workspace
    end

    # Reads every subscription account's state from the proxy, refreshes their models, and orders each subscription's
    # sign-ins so a new conversation goes to the one with room whose limit resets soonest.
    def sync!(credentials = client.credentials)
      by_name = credentials.index_by(&:name)
      accounts = @workspace.workspace_ai_accounts.subscriptions.where.not(proxy_credential: nil).to_a
      accounts.each do |account|
        credential = by_name[account.proxy_credential]
        next account.update_columns(proxy_state: account.proxy_state.merge("signed_out" => true), updated_at: Time.current) unless credential

        account.update_columns(proxy_state: account.proxy_state.merge(state_of(credential)), updated_at: Time.current)
      end
      refresh_models!(accounts)
      rank!(accounts)
    end

    def refresh_models!(accounts = @workspace.workspace_ai_accounts.subscriptions.where.not(proxy_credential: nil).to_a)
      return if accounts.empty?

      facts = client.models_for(@workspace).index_by(&:id)
      prefix = SubscriptionProxy.prefix_for(@workspace)
      accounts.each do |account|
        served = client.credential_models(account.proxy_credential, prefix: prefix)
        models = served.filter_map { |id| facts[id]&.to_h&.stringify_keys }
        account.update_columns(proxy_state: account.proxy_state.merge("models" => models), updated_at: Time.current) if models.any?
      end
    end

    # Within each subscription, the sign-ins with room come first, the one whose limit resets soonest first, then those
    # whose limit is not known, then those at their limit. The proxy keeps a conversation on the sign-in it started on.
    def rank!(accounts)
      accounts.group_by(&:provider).each_value do |group|
        ordered = group.sort_by { |account| rank_key(account) }
        ordered.each_with_index do |account, index|
          priority = ordered.size - index
          next if account.proxy_state.to_h["priority"] == priority

          client.prioritize(account.proxy_credential, priority)
          account.update_columns(proxy_state: account.proxy_state.merge("priority" => priority), updated_at: Time.current)
        end
      end
    end

    def switch!(account, on:)
      client.switch(account.proxy_credential, on: on) if account.proxy_credential.present?
      on ? account.enable! : account.disable!
    end

    # The sign-in is removed from the proxy before the account, so a sign-in never outlives the account that names it.
    def disconnect!(account)
      client.delete(account.proxy_credential) if account.proxy_credential.present?
      account.destroy!
    end

    # Removes finished sign-ins no workspace claimed, once nothing can still claim them. The proxy's credentials are all
    # workspaces', so this runs once for the install.
    def self.sweep_unclaimed!(credentials)
      claimed = WorkspaceAiAccount.where(proxy_credential: credentials.map(&:name)).pluck(:proxy_credential)
      stale = credentials.reject { |credential| claimed.include?(credential.name) }
                         .select { |credential| credential.created_at.nil? || credential.created_at < UNCLAIMED_AFTER.ago }
      client = Client.new
      stale.each do |credential|
        client.delete(credential.name)
        Rails.logger.info({ event: "subscription_proxy.unclaimed_removed", provider: credential.provider }.to_json)
      end
    end

    # What one credential says of its limit and its sign-in, as the account keeps it.
    def state_of(credential)
      limit = limit_of(credential)
      { "signed_out" => signed_out?(credential), "limit" => limit, "email" => credential.email }.compact
    end

    private

    def client = @client ||= Client.new(workspace: @workspace)

    def rank_key(account)
      limit = account.proxy_limit
      return [ 2, 0 ] if account.limit_reached? || account.signed_out?

      resets = limit["resets_at"].present? ? Time.zone.parse(limit["resets_at"].to_s).to_i : nil
      resets ? [ 0, resets ] : [ 1, 0 ]
    end

    # A sign-in the provider refused for good is in error with no time to try again.
    def signed_out?(credential)
      credential.status == "error" && credential.next_retry_after.nil?
    end

    def limit_of(credential)
      windows = LIMIT_WINDOWS.filter_map { |window| window_of(credential, window) }
      busiest = windows.max_by { |window| window[:used] }
      reached = credential.next_retry_after if credential.unavailable && credential.next_retry_after&.future?
      reached ||= busiest[:resets_at] if busiest && busiest[:used] >= 100
      {
        "left_percent" => busiest && [ 100 - busiest[:used].round, 0 ].max,
        "resets_at" => (busiest && busiest[:resets_at]&.iso8601) || reached&.iso8601,
        "reached_until" => reached&.iso8601,
        "reported" => windows.any?
      }.compact
    end

    def window_of(credential, window)
      used = credential.quota["x-codex-#{window}-used-percent"]
      return nil if used.blank?

      resets_at = reset_time(credential, window)
      { used: used.to_f, resets_at: resets_at }
    end

    def reset_time(credential, window)
      at = credential.quota["x-codex-#{window}-reset-at"]
      return Time.zone.at(at.to_i) if at.to_s.match?(/\A\d+\z/)
      return Time.zone.parse(at.to_s) if at.present?

      after = credential.quota["x-codex-#{window}-reset-after-seconds"]
      (credential.quota_observed_at || Time.current) + after.to_i.seconds if after.present?
    rescue ArgumentError
      nil
    end
  end
end
