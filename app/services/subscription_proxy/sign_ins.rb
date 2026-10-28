module SubscriptionProxy
  # Connecting a workspace's AI subscription: the proxy starts a sign-in named by the sign-in's own id and workspace,
  # the person finishes it with the provider (a code to enter, or an address to paste back), and the proxy saves the
  # credential already stamped with both (deploy/subscription-proxy/firefight_sign_in.go). The credential is then found
  # by the sign-in's id, never guessed at, and the account is made for it.
  class SignIns
    Failed = Class.new(StandardError)
    # The proxy could not be asked, which is said once while the sign-in keeps waiting.
    StillWaiting = Class.new(StandardError)

    # How long a request waits for the sweep of the same kind before the page asks again.
    LOCK_WAIT = 3.seconds

    UNAVAILABLE = SubscriptionProxy::UNAVAILABLE
    UNREACHABLE_WHILE_WAITING = "Firefight cannot reach the subscription service right now. Your sign-in is kept and finishes once it answers again.".freeze
    TIMED_OUT = "The sign-in timed out before it finished. Start again.".freeze
    NOT_THE_ADDRESS = "That is not the address this sign-in sent your browser to. Copy the whole address from the address bar after you sign in, and paste it here.".freeze
    TAKEN = "This account is already connected to another Firefight workspace. Disconnect it there first, or sign in with another account.".freeze
    NOTHING_NEW = "The sign-in finished, but no account came of it. Start again.".freeze
    CANCELLED = "The sign-in was cancelled.".freeze

    # The account connected or signed in again, or nil while the person has not finished.
    # fresh is false when another request already settled it, which already said so.
    Outcome = Data.define(:account, :reconnected, :fresh)

    def initialize(workspace, by:)
      @workspace = workspace
      @by = by
    end

    # A person has one sign-in at a time, so starting another cancels theirs that was waiting. The sign-in's id is
    # chosen first, since the proxy is told it when the sign-in starts.
    def start!(subscription_key, site: nil, account: nil)
      raise Failed, UNAVAILABLE unless SubscriptionProxy.usable?

      subscription = AiSubscriptions.find(subscription_key) || raise(Failed, "That is not a subscription Firefight connects.")
      chosen = site.present? ? subscription.site(site) : subscription.sites.first
      raise Failed, "That is not a place #{subscription.name} signs in." unless chosen

      SubscriptionSignIn.waiting.where(workspace: @workspace, started_by: @by).find_each { |waiting| cancel!(waiting) }
      id = SecureRandom.uuid
      started = client.start_sign_in(chosen.proxy, sign_in_id: id)
      SubscriptionSignIn.create!(
        id: id, workspace: @workspace, started_by: @by, workspace_ai_account: account, subscription: subscription.key, proxy: chosen.proxy,
        state: started.state, url: started.url, user_code: started.user_code,
        expires_at: started.expires_at || SubscriptionSignIn::PASTE_WAIT.from_now
      )
    rescue SubscriptionProxy::Error
      raise Failed, UNAVAILABLE
    end

    # Signing an account in again goes where it signed in first.
    def start_again!(account) = start!(account.provider, site: account.proxy_state.to_h["proxy"], account: account)

    # The address the person's browser landed on after signing in. Only this sign-in's own state is taken, so one
    # workspace can never finish another's. It looks once whether that finished it, and the page asks again after. Once
    # the proxy has the code it is not asked for again, even when the look fails.
    def hand_back!(sign_in, address)
      return finished(sign_in) unless sign_in.waiting?

      query = Rack::Utils.parse_query(URI.parse(address.to_s.strip).query.to_s)
      raise Failed, NOT_THE_ADDRESS unless query["state"] == sign_in.state && query["code"].present?

      begin
        client.finish_sign_in(sign_in.proxy, state: sign_in.state, code: query["code"])
      rescue SubscriptionProxy::Error
        raise Failed, UNAVAILABLE
      end
      begin
        advance!(sign_in)
      rescue StillWaiting
        nil
      end
    rescue URI::InvalidURIError
      raise Failed, NOT_THE_ADDRESS
    end

    # Asks the proxy whether the person finished. Answers the Outcome once they did and nil while they have not. Raises
    # Failed with why it will not finish, and StillWaiting the first time the proxy cannot be asked. A sign-in the proxy
    # finished is taken up even when it finished just before its time ran out.
    def advance!(sign_in)
      return finished(sign_in) unless sign_in.waiting?

      status = client.sign_in_status(sign_in.state)
      answered_again!(sign_in)
      return claim!(sign_in) if status == :done
      return timed_out!(sign_in) if sign_in.expired?
      return nil if status == :waiting

      fail!(sign_in, refused_because(sign_in) || "The sign-in did not finish: #{status.to_s.strip.delete_suffix('.')}. Start again.")
    rescue SubscriptionProxy::Error
      unreachable!(sign_in)
    end

    # Kept, so a credential the proxy saved from it before it was cancelled is found and removed (Accounts.sweep!).
    # Answers whether this request cancelled it, false when it had already finished.
    def cancel!(sign_in)
      return false unless sign_in.settle!(SubscriptionSignIn::STATUS_CANCELLED, error: CANCELLED)

      begin
        client.cancel_sign_in(sign_in.state)
      rescue SubscriptionProxy::Error => error
        Rails.logger.warn({ event: "subscription_proxy.cancel_unsent", sign_in_id: sign_in.id, error: error.message }.to_json)
      end
      true
    end

    private

    def client = @client ||= Client.new(workspace: @workspace)

    def fail!(sign_in, reason)
      sign_in.settle!(SubscriptionSignIn::STATUS_FAILED, error: reason)
      raise Failed, reason
    end

    # The proxy stops waiting on it too, so the provider approving it later saves nothing.
    def timed_out!(sign_in)
      begin
        client.cancel_sign_in(sign_in.state)
      rescue SubscriptionProxy::Error
        nil
      end
      fail!(sign_in, TIMED_OUT)
    end

    # Said once: the error is written only on a waiting sign-in that has none yet.
    def unreachable!(sign_in)
      first = SubscriptionSignIn.where(id: sign_in.id, status: SubscriptionSignIn::STATUS_WAITING, error: nil)
                                .update_all(error: UNREACHABLE_WHILE_WAITING, updated_at: Time.current) == 1
      raise StillWaiting, UNREACHABLE_WHILE_WAITING if first

      nil
    end

    def answered_again!(sign_in)
      SubscriptionSignIn.where(id: sign_in.id, status: SubscriptionSignIn::STATUS_WAITING).where.not(error: nil).update_all(error: nil)
    end

    # Without the proxy's word on why, the sign-in still ends with what the proxy said of it.
    def refused_because(sign_in)
      TAKEN if client.sign_in_refusal(sign_in.id) == Client::REFUSED_TAKEN
    rescue SubscriptionProxy::Error
      nil
    end

    # A sign-in another request already settled answers what that request found.
    def finished(sign_in)
      raise Failed, sign_in.error.presence || NOTHING_NEW unless sign_in.status == SubscriptionSignIn::STATUS_DONE

      Outcome.new(account: @workspace.workspace_ai_accounts.find_by(id: sign_in.workspace_ai_account_id), reconnected: false, fresh: false)
    end

    # The credential this sign-in made is the one carrying its id. The proxy lists it a moment after it is saved, so
    # until then the sign-in waits. The sweep of the same kind never runs meanwhile.
    def claim!(sign_in)
      result = ClaimLock.hold(sign_in.proxy, wait: LOCK_WAIT) do
        sign_in.reload
        next finished(sign_in) unless sign_in.waiting?

        credential = client.credentials.find { |candidate| candidate.provider == sign_in.proxy && candidate.sign_in_id == sign_in.id }
        unless credential
          fail!(sign_in, NOTHING_NEW) if sign_in.expired?
          next nil
        end

        holder = WorkspaceAiAccount.find_by(proxy_credential: credential.name)
        if holder && holder.workspace_id != @workspace.id
          fail!(sign_in, TAKEN)
        elsif holder
          signed_in_again!(sign_in, holder)
        else
          connect!(sign_in, credential)
        end
      end
      result == ClaimLock::BUSY ? nil : result
    end

    # The same login signed in again keeps the credential it had, with fresh tokens and the workspace's prefix.
    def signed_in_again!(sign_in, account)
      account.update_columns(failing_since: nil, last_error: nil, proxy_state: account.proxy_state.merge("signed_out" => false), updated_at: Time.current)
      return finished(sign_in.reload) unless settle_done!(sign_in, account)

      Outcome.new(account: account.reload, reconnected: true, fresh: true)
    end

    def connect!(sign_in, credential)
      state = Accounts.new(@workspace).state_of(credential).merge("models" => models_of(credential), "proxy" => sign_in.proxy)
      replacing = sign_in.workspace_ai_account
      account = replacing ? reconnect_with(replacing, credential, state) : new_account(sign_in, credential, state)
      return finished(sign_in.reload) unless settle_done!(sign_in, account)

      Outcome.new(account: account.reload, reconnected: replacing.present?, fresh: true)
    rescue ActiveRecord::RecordNotUnique
      finished(sign_in.reload)
    rescue ActiveRecord::RecordInvalid => error
      client.delete(credential.name)
      fail!(sign_in, "The sign-in finished, but #{error.record.errors.full_messages.to_sentence.downcase_first}. Start again.")
    end

    def settle_done!(sign_in, account)
      SubscriptionSignIn.where(id: sign_in.id, status: SubscriptionSignIn::STATUS_WAITING)
                        .update_all(status: SubscriptionSignIn::STATUS_DONE, error: nil, workspace_ai_account_id: account.id, updated_at: Time.current) == 1
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

    # Signed in again with another login: the account takes the new credential and the old one is removed. An old one
    # the proxy cannot remove now is no longer named by any account, so the sweep removes it later.
    def reconnect_with(account, credential, state)
      old = account.proxy_credential
      account.update_columns(proxy_credential: credential.name, credential_hint: credential.email, failing_since: nil, last_error: nil,
                             proxy_state: state, updated_at: Time.current)
      begin
        client.delete(old) if old.present? && old != credential.name
      rescue SubscriptionProxy::Error => error
        Rails.logger.warn({ event: "subscription_proxy.replaced_not_removed", account_id: account.id, error: error.message }.to_json)
      end
      account
    end
  end
end
