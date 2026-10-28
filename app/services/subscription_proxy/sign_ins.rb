module SubscriptionProxy
  # Connecting a workspace's AI subscription: the proxy starts a sign-in, the person finishes it with the provider (a
  # code to enter, or an address to paste back), and the credential the proxy then holds is claimed for the workspace by
  # giving it the workspace's prefix. The proxy does not say which credential a sign-in made, so the one claimed is the
  # one new credential of that kind no workspace holds, and when two sign-ins of one kind finish together neither is
  # guessed at: both are asked to sign in again.
  class SignIns
    Failed = Class.new(StandardError)

    # The proxy's clock and Firefight's may differ a little.
    CLOCK_SKEW = 1.minute
    # How long finishing a pasted sign-in is waited for before the page asks again.
    FINISH_WAIT = 8.seconds
    FINISH_POLL = 0.5
    LOCK_WAIT = 20.seconds

    UNAVAILABLE = SubscriptionProxy::UNAVAILABLE
    TIMED_OUT = "The sign-in timed out before it finished. Start again.".freeze
    NOT_THE_ADDRESS = "That is not the address this sign-in sent your browser to. Copy the whole address from the address bar after you sign in, and paste it here.".freeze
    TAKEN = "This account is already connected to another Firefight workspace. Disconnect it there first, or sign in with another account.".freeze
    NOTHING_NEW = "The sign-in finished, but no new account came of it. Start again.".freeze
    AT_ONCE = "Another sign-in to the same service finished at the same moment, so Firefight could not tell them apart. Start again.".freeze

    # The account connected or signed in again, or nil while the person has not finished.
    # fresh is false when another request already settled it, which already said so.
    Outcome = Data.define(:account, :reconnected, :fresh)

    def initialize(workspace, by:)
      @workspace = workspace
      @by = by
    end

    # A person has one sign-in at a time, so starting another drops theirs that was waiting.
    def start!(subscription_key, site: nil, account: nil)
      raise Failed, UNAVAILABLE unless SubscriptionProxy.usable?

      subscription = AiSubscriptions.find(subscription_key) || raise(Failed, "That is not a subscription Firefight connects.")
      chosen = site.present? ? subscription.site(site) : subscription.sites.first
      raise Failed, "That is not a place #{subscription.name} signs in." unless chosen

      SubscriptionSignIn.waiting.where(workspace: @workspace, started_by: @by).find_each { |waiting| cancel!(waiting) }
      started = client.start_sign_in(chosen.proxy)
      SubscriptionSignIn.create!(
        workspace: @workspace, started_by: @by, workspace_ai_account: account, subscription: subscription.key, proxy: chosen.proxy,
        state: started.state, url: started.url, user_code: started.user_code,
        expires_at: started.expires_at || SubscriptionSignIn::PASTE_WAIT.from_now
      )
    rescue SubscriptionProxy::Error
      raise Failed, UNAVAILABLE
    end

    # Signing an account in again goes where it signed in first.
    def start_again!(account) = start!(account.provider, site: account.proxy_state.to_h["proxy"], account: account)

    # The address the person's browser landed on after signing in. Only this sign-in's own state is taken, so one
    # workspace can never finish another's.
    def hand_back!(sign_in, address)
      query = Rack::Utils.parse_query(URI.parse(address.to_s.strip).query.to_s)
      raise Failed, NOT_THE_ADDRESS unless query["state"] == sign_in.state && query["code"].present?

      client.finish_sign_in(sign_in.proxy, state: sign_in.state, code: query["code"])
      deadline = FINISH_WAIT.from_now
      loop do
        outcome = advance!(sign_in)
        return outcome if outcome || Time.current > deadline

        Kernel.sleep FINISH_POLL
      end
    rescue URI::InvalidURIError
      raise Failed, NOT_THE_ADDRESS
    rescue SubscriptionProxy::Error
      raise Failed, UNAVAILABLE
    end

    # Asks the proxy whether the person finished. Answers the Outcome once they did, nil while they have not, and
    # raises Failed with why it will not finish.
    def advance!(sign_in)
      return finished(sign_in) unless sign_in.status == SubscriptionSignIn::STATUS_WAITING

      status = client.sign_in_status(sign_in.state)
      return fail!(sign_in, TIMED_OUT) if status == :waiting && sign_in.expired?
      return nil if status == :waiting
      return fail!(sign_in, "The sign-in did not finish: #{status.to_s.strip.delete_suffix(".")}. Start again.") unless status == :done

      claim!(sign_in)
    rescue SubscriptionProxy::Error
      raise Failed, UNAVAILABLE
    end

    def cancel!(sign_in)
      client.cancel_sign_in(sign_in.state) if sign_in.status == SubscriptionSignIn::STATUS_WAITING
      sign_in.destroy!
    rescue SubscriptionProxy::Error
      sign_in.destroy!
    end

    private

    def client = @client ||= Client.new(workspace: @workspace)

    def fail!(sign_in, reason)
      sign_in.settle!(SubscriptionSignIn::STATUS_FAILED, error: reason)
      raise Failed, reason
    end

    # A sign-in another request already settled answers what that request found.
    def finished(sign_in)
      raise Failed, sign_in.error.presence || NOTHING_NEW if sign_in.status == SubscriptionSignIn::STATUS_FAILED

      Outcome.new(account: @workspace.workspace_ai_accounts.find_by(id: sign_in.workspace_ai_account_id), reconnected: false, fresh: false)
    end

    # One claim at a time for each kind of sign-in across the install, so two workspaces never claim from the same list.
    # The lock is a session's own, on a connection of its own, so no transaction stays open while the proxy answers.
    def locked(proxy)
      holder = SubscriptionSignIn.connection_pool.db_config.new_connection
      asked = SubscriptionSignIn.sanitize_sql([ "SELECT pg_try_advisory_lock(hashtextextended(?, 0))", "subscription_sign_in:#{proxy}" ])
      deadline = LOCK_WAIT.from_now
      until holder.select_value(asked) == true
        raise Failed, UNAVAILABLE if Time.current > deadline

        Kernel.sleep FINISH_POLL
      end
      yield
    ensure
      holder&.disconnect!
    end

    def claim!(sign_in)
      locked(sign_in.proxy) do
        sign_in.reload
        next finished(sign_in) unless sign_in.status == SubscriptionSignIn::STATUS_WAITING

        credentials = client.credentials.select { |credential| credential.provider == sign_in.proxy }
        claimed = WorkspaceAiAccount.where(proxy_credential: credentials.map(&:name)).to_a.index_by(&:proxy_credential)
        since = sign_in.created_at - CLOCK_SKEW
        fresh = credentials.reject { |credential| claimed.key?(credential.name) }.select { |credential| credential.created_at.nil? || credential.created_at >= since }
        rivals = finished_rivals(sign_in)

        if fresh.size == 1 && rivals.empty?
          connect!(sign_in, fresh.first)
        elsif fresh.empty? && rivals.empty?
          signed_in_again!(sign_in, credentials, claimed, since)
        else
          fresh.each { |credential| client.delete(credential.name) }
          rivals.each { |rival| rival.settle!(SubscriptionSignIn::STATUS_FAILED, error: AT_ONCE) }
          fail!(sign_in, AT_ONCE)
        end
      end
    end

    # Other people's sign-ins of the same kind that the proxy says finished and Firefight has not settled yet.
    def finished_rivals(sign_in)
      SubscriptionSignIn.waiting.where(proxy: sign_in.proxy).where.not(id: sign_in.id).select do |rival|
        client.sign_in_status(rival.state) == :done
      end
    end

    # The same account signed in again keeps the credential it had, with fresh tokens and the prefix it already carries.
    def signed_in_again!(sign_in, credentials, claimed, since)
      touched = credentials.select { |credential| credential.updated_at.nil? || credential.updated_at >= since }.filter_map { |credential| claimed[credential.name] }
      ours = touched.find { |account| account.workspace_id == @workspace.id }
      fail!(sign_in, touched.any? ? TAKEN : NOTHING_NEW) unless ours

      ours.update_columns(failing_since: nil, last_error: nil, proxy_state: ours.proxy_state.merge("signed_out" => false), updated_at: Time.current)
      sign_in.update_columns(workspace_ai_account_id: ours.id)
      sign_in.settle!(SubscriptionSignIn::STATUS_DONE)
      Outcome.new(account: ours.reload, reconnected: true, fresh: true)
    end

    # The prefix goes on before the account is saved, so a credential this workspace holds is only ever reachable with
    # its prefix. A save that fails takes the credential away again.
    def connect!(sign_in, credential)
      client.claim(credential.name, prefix: SubscriptionProxy.prefix_for(@workspace))
      state = Accounts.new(@workspace).state_of(credential).merge("models" => models_of(credential), "proxy" => sign_in.proxy)
      replacing = sign_in.workspace_ai_account
      account = replacing ? reconnect_with(replacing, credential, state) : new_account(sign_in, credential, state)
      sign_in.update_columns(workspace_ai_account_id: account.id)
      sign_in.settle!(SubscriptionSignIn::STATUS_DONE)
      Outcome.new(account: account.reload, reconnected: replacing.present?, fresh: true)
    rescue ActiveRecord::RecordInvalid => error
      client.delete(credential.name)
      fail!(sign_in, "The sign-in finished, but #{error.record.errors.full_messages.to_sentence.downcase_first}. Start again.")
    end

    def models_of(credential)
      facts = client.models_for(@workspace).index_by(&:id)
      client.credential_models(credential.name, prefix: SubscriptionProxy.prefix_for(@workspace)).filter_map { |id| facts[id]&.to_h&.stringify_keys }
    end

    def new_account(sign_in, credential, state)
      subscription = sign_in.subscription_definition
      label = [ subscription.name, credential.email ].compact.join(", ").truncate(WorkspaceAiAccount::LABEL_LIMIT)
      account = @workspace.workspace_ai_accounts.new(
        kind: AiProviders::KIND_SUBSCRIPTION, provider: subscription.key, label: label, created_by: @by,
        proxy_credential: credential.name, credential_hint: credential.email, proxy_state: state
      )
      account.assign_models({})
      account.save_in_position!
      account
    end

    # Signed in again with another login: the account takes the new credential and the old one is removed.
    def reconnect_with(account, credential, state)
      old = account.proxy_credential
      account.update_columns(proxy_credential: credential.name, credential_hint: credential.email, failing_since: nil, last_error: nil,
                             proxy_state: state, updated_at: Time.current)
      client.delete(old) if old.present? && old != credential.name
      account
    end
  end
end
