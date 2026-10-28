module SubscriptionProxy
  # Connecting a workspace's AI subscription: the proxy starts a sign-in, the person finishes it with the provider (a
  # code to enter, or an address to paste back), and the credential the proxy then holds is claimed for the workspace by
  # giving it the workspace's prefix. The proxy does not say which credential a sign-in made, so a credential is claimed
  # only when this sign-in is the one sign-in of its kind that could have made it, from when each started and ended.
  # Anything else is never guessed at: the credentials are removed and the person signs in again.
  class SignIns
    Failed = Class.new(StandardError)
    # The proxy could not be asked, which is said once while the sign-in keeps waiting.
    StillWaiting = Class.new(StandardError)

    # How long a request waits for another claim of the same kind before the page asks again.
    LOCK_WAIT = 3.seconds
    # The most other sign-ins still waiting that a claim asks the proxy about. Past it the claim is not guessed at.
    RIVALS_ASKED = 5
    # Ended sign-ins older than this cannot have made a credential that is still unclaimed.
    RIVALS_LOOK_BACK = 1.day

    UNAVAILABLE = SubscriptionProxy::UNAVAILABLE
    UNREACHABLE_WHILE_WAITING = "Firefight cannot reach the subscription service right now. Your sign-in is kept and finishes once it answers again.".freeze
    TIMED_OUT = "The sign-in timed out before it finished. Start again.".freeze
    NOT_THE_ADDRESS = "That is not the address this sign-in sent your browser to. Copy the whole address from the address bar after you sign in, and paste it here.".freeze
    TAKEN = "This account is already connected to another Firefight workspace. Disconnect it there first, or sign in with another account.".freeze
    NOTHING_NEW = "The sign-in finished, but no new account came of it. Start again.".freeze
    AT_ONCE = "Another sign-in to the same service finished around the same time, so Firefight could not tell them apart. Start again.".freeze
    CANCELLED = "The sign-in was cancelled.".freeze

    # The account connected or signed in again, or nil while the person has not finished.
    # fresh is false when another request already settled it, which already said so.
    Outcome = Data.define(:account, :reconnected, :fresh)

    def initialize(workspace, by:)
      @workspace = workspace
      @by = by
    end

    # A person has one sign-in at a time, so starting another cancels theirs that was waiting.
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
    # workspace can never finish another's. It looks once whether that finished it, and the page asks again after.
    def hand_back!(sign_in, address)
      return finished(sign_in) unless sign_in.waiting?
      return fail!(sign_in, TIMED_OUT) if sign_in.expired?

      query = Rack::Utils.parse_query(URI.parse(address.to_s.strip).query.to_s)
      raise Failed, NOT_THE_ADDRESS unless query["state"] == sign_in.state && query["code"].present?

      begin
        client.finish_sign_in(sign_in.proxy, state: sign_in.state, code: query["code"])
      rescue SubscriptionProxy::Error
        raise Failed, UNAVAILABLE
      end
      advance!(sign_in)
    rescue URI::InvalidURIError
      raise Failed, NOT_THE_ADDRESS
    end

    # Asks the proxy whether the person finished. Answers the Outcome once they did and nil while they have not. Raises
    # Failed with why it will not finish, and StillWaiting the first time the proxy cannot be asked.
    def advance!(sign_in)
      return finished(sign_in) unless sign_in.waiting?
      return fail!(sign_in, TIMED_OUT) if sign_in.expired?

      status = client.sign_in_status(sign_in.state)
      sign_in.update_columns(error: nil) if sign_in.error.present?
      return nil if status == :waiting
      return fail!(sign_in, "The sign-in did not finish: #{status.to_s.strip.delete_suffix('.')}. Start again.") unless status == :done

      claim!(sign_in)
    rescue SubscriptionProxy::Error
      unreachable!(sign_in)
    end

    # Kept, so a credential the proxy made from it before it was cancelled is never claimed by another sign-in.
    def cancel!(sign_in)
      return unless sign_in.settle!(SubscriptionSignIn::STATUS_CANCELLED, error: CANCELLED)

      client.cancel_sign_in(sign_in.state)
    rescue SubscriptionProxy::Error
      nil
    end

    private

    def client = @client ||= Client.new(workspace: @workspace)

    def fail!(sign_in, reason)
      sign_in.settle!(SubscriptionSignIn::STATUS_FAILED, error: reason)
      raise Failed, reason
    end

    def unreachable!(sign_in)
      return nil if sign_in.error.present?

      sign_in.update_columns(error: UNREACHABLE_WHILE_WAITING)
      raise StillWaiting, UNREACHABLE_WHILE_WAITING
    end

    # A sign-in another request already settled answers what that request found.
    def finished(sign_in)
      raise Failed, sign_in.error.presence || NOTHING_NEW unless sign_in.status == SubscriptionSignIn::STATUS_DONE

      Outcome.new(account: @workspace.workspace_ai_accounts.find_by(id: sign_in.workspace_ai_account_id), reconnected: false, fresh: false)
    end

    # Another claim of the same kind holding the lock leaves this one waiting, and the page asks again.
    def claim!(sign_in)
      result = ClaimLock.hold(sign_in.proxy, wait: LOCK_WAIT) do
        sign_in.reload
        next finished(sign_in) unless sign_in.waiting?

        credentials = client.credentials.select { |credential| credential.provider == sign_in.proxy }
        claimed = WorkspaceAiAccount.where(proxy_credential: credentials.map(&:name)).to_a.index_by(&:proxy_credential)
        unclaimed = credentials.reject { |credential| claimed.key?(credential.name) }
        fresh = unclaimed.select { |credential| sign_in.could_have_made?(made_at(credential)) }
        next signed_in_again!(sign_in, credentials, claimed) if fresh.empty?

        rivals = fresh.flat_map { |credential| rivals_for(sign_in, credential, unclaimed - fresh) }.uniq
        next connect!(sign_in, fresh.first) if fresh.size == 1 && rivals.empty?

        fresh.each { |credential| client.delete(credential.name) }
        rivals.select(&:waiting?).each { |rival| rival.settle!(SubscriptionSignIn::STATUS_FAILED, error: AT_ONCE) }
        fail!(sign_in, AT_ONCE)
      end
      result == ClaimLock::BUSY ? nil : result
    end

    # A credential with no time of its own is taken as made now, which no ended sign-in can account for.
    def made_at(credential) = credential.created_at || Time.current

    # The other sign-ins of the kind that could have made the credential: ended ones whose time covers it, and waiting
    # ones the proxy says finished. One that another unclaimed credential outside this sign-in's time accounts for is
    # not counted, since a sign-in makes one credential.
    def rivals_for(sign_in, credential, accounted)
      at = made_at(credential)
      others = SubscriptionSignIn.where(proxy: sign_in.proxy).where.not(id: sign_in.id).where(created_at: RIVALS_LOOK_BACK.ago..)
                                 .select { |other| other.could_have_made?(at) }
                                 .reject { |other| accounted.any? { |elsewhere| other.could_have_made?(made_at(elsewhere)) } }
      ended, waiting = others.partition { |other| !other.waiting? }
      return others if waiting.size > RIVALS_ASKED

      ended + waiting.select { |other| client.sign_in_status(other.state) == :done }
    end

    # The same account signed in again keeps the credential it had, with fresh tokens and the prefix it already carries.
    def signed_in_again!(sign_in, credentials, claimed)
      touched = credentials.select { |credential| credential.updated_at.nil? || sign_in.could_have_made?(credential.updated_at) }
                           .filter_map { |credential| claimed[credential.name] }
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
