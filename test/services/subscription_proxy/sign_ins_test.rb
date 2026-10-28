require "test_helper"

class SubscriptionProxy::SignInsTest < ActiveSupport::TestCase
  Client = SubscriptionProxy::Client

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    subscription_proxy_up!
    @service = SubscriptionProxy::SignIns.new(@workspace, by: @member)
    Client.any_instance.stubs(:models_for).returns([ proxy_model("gpt-6.1-sol"), proxy_model("gpt-6-luna") ])
    Client.any_instance.stubs(:credential_models).returns(%w[gpt-6.1-sol gpt-6-luna])
  end

  def start(subscription = "chatgpt", state: "state-#{SecureRandom.hex(4)}", service: @service, **)
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: state, url: "https://auth.openai.com/oauth/authorize?state=#{state}", user_code: nil, expires_at: nil))
    service.start!(subscription, **)
  end

  test "the proxy is told the sign-in's own id when it starts, so the credential it saves names it" do
    Client.any_instance.expects(:start_sign_in).with("codex", sign_in_id: instance_of(String))
          .returns(Client::SignIn.new(state: "s", url: "https://auth.openai.com", user_code: nil, expires_at: nil))

    sign_in = @service.start!("chatgpt")

    assert_match SubscriptionProxy::ModelFacts::UUID, sign_in.id
  end

  test "a finished sign-in becomes the account for exactly the credential carrying its id" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([
      proxy_credential(name: "codex-ben.json", email: "ben@example.com", sign_in_id: SecureRandom.uuid),
      proxy_credential(name: "codex-ana.json", sign_in_id: sign_in.id)
    ])

    outcome = @service.advance!(sign_in)

    account = outcome.account
    assert_equal [ AiProviders::KIND_SUBSCRIPTION, "chatgpt", "codex-ana.json", "ana@example.com" ], [ account.kind, account.provider, account.proxy_credential, account.credential_hint ]
    assert_equal [ "gpt-6.1-sol", "gpt-6-luna" ], [ account.model_for(WorkspaceAiAccount::MAIN), account.model_for(WorkspaceAiAccount::FAST) ]
    assert_equal SubscriptionSignIn::STATUS_DONE, sign_in.reload.status
    assert outcome.fresh
  end

  test "two workspaces finishing sign-ins of one kind together each get their own credential" do
    other = workspaces(:slack_workspace_two)
    theirs_service = SubscriptionProxy::SignIns.new(other, by: nil)
    mine = start
    theirs = start(service: theirs_service)
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([
      proxy_credential(name: "codex-ana.json", sign_in_id: mine.id),
      proxy_credential(name: "codex-ben.json", email: "ben@example.com", sign_in_id: theirs.id)
    ])

    assert_equal "codex-ana.json", @service.advance!(mine).account.proxy_credential
    assert_equal "codex-ben.json", theirs_service.advance!(theirs).account.proxy_credential
  end

  test "a finished sign-in whose credential the proxy does not list yet keeps waiting" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ben.json", sign_in_id: SecureRandom.uuid) ])

    assert_nil @service.advance!(sign_in)
    assert sign_in.reload.waiting?
  end

  test "the same login already connected to another workspace is refused by the proxy, and said so plainly" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns("Failed to save authentication tokens: firefight: this account is already connected to another workspace")
    Client.any_instance.expects(:sign_in_refusal).with(sign_in.id).returns(Client::REFUSED_TAKEN)

    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(sign_in) }

    assert_equal SubscriptionProxy::SignIns::TAKEN, error.message
    assert_equal SubscriptionSignIn::STATUS_FAILED, sign_in.reload.status
    assert_empty @workspace.workspace_ai_accounts.subscriptions
  end

  test "a credential another workspace's account names is never taken over" do
    add_subscription_account!(workspaces(:slack_workspace_two), credential: "codex-ana.json")
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", sign_in_id: sign_in.id) ])

    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(sign_in) }

    assert_equal SubscriptionProxy::SignIns::TAKEN, error.message
    assert_empty @workspace.workspace_ai_accounts.subscriptions
  end

  test "signing the same account in again keeps its credential and clears what was wrong" do
    account = add_subscription_account!(@workspace, credential: "codex-ana.json", state: { "signed_out" => true })
    sign_in = start(account: account)
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", created_at: 1.day.ago, updated_at: Time.current, sign_in_id: sign_in.id) ])

    outcome = @service.advance!(sign_in)

    assert outcome.reconnected
    assert_equal :verified, outcome.account.tap { |found| found.update_columns(verified_at: Time.current) }.state
  end

  test "a pasted address is handed back only when it carries this sign-in's own state" do
    sign_in = start(state: "mine")
    Client.any_instance.expects(:finish_sign_in).never

    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.hand_back!(sign_in, "http://localhost:1455/auth/callback?code=c&state=someone-else") }
    assert_equal SubscriptionProxy::SignIns::NOT_THE_ADDRESS, error.message
  end

  test "a pasted address finishes the sign-in once the proxy has the code" do
    sign_in = start(state: "mine")
    Client.any_instance.expects(:finish_sign_in).with("codex", state: "mine", code: "the-code")
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", sign_in_id: sign_in.id) ])

    outcome = @service.hand_back!(sign_in, "http://localhost:1455/auth/callback?code=the-code&state=mine")

    assert_equal "codex-ana.json", outcome.account.proxy_credential
  end

  test "a code the proxy took is not asked for again when the look after it cannot reach the proxy" do
    sign_in = start(state: "mine")
    Client.any_instance.stubs(:finish_sign_in)
    Client.any_instance.stubs(:sign_in_status).raises(SubscriptionProxy::Error, "down")

    assert_nil @service.hand_back!(sign_in, "http://localhost:1455/auth/callback?code=c&state=mine")
    assert sign_in.reload.waiting?
  end

  test "a sign-in still waiting says nothing, and one past its time is ended" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:waiting)
    assert_nil @service.advance!(sign_in)

    Client.any_instance.expects(:cancel_sign_in).with(sign_in.state)
    sign_in.update_columns(expires_at: 1.minute.ago)
    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(sign_in) }
    assert_equal SubscriptionProxy::SignIns::TIMED_OUT, error.message
  end

  test "a sign-in the proxy finished just before its time ran out is taken up, not reported timed out" do
    sign_in = start
    sign_in.update_columns(expires_at: 1.second.ago)
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", sign_in_id: sign_in.id) ])

    assert_equal "codex-ana.json", @service.advance!(sign_in).account.proxy_credential
  end

  test "a finished sign-in past its time whose credential never appeared ends" do
    sign_in = start
    sign_in.update_columns(expires_at: 1.minute.ago)
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([])

    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(sign_in) }
    assert_equal SubscriptionProxy::SignIns::NOTHING_NEW, error.message
  end

  test "the proxy being out of reach is said once, and never written over a sign-in another request settled" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).raises(SubscriptionProxy::Error, "down")

    assert_raises(SubscriptionProxy::SignIns::StillWaiting) { @service.advance!(sign_in) }
    assert_nil @service.advance!(sign_in)

    stale = SubscriptionSignIn.find(sign_in.id)
    sign_in.settle!(SubscriptionSignIn::STATUS_CANCELLED, error: SubscriptionProxy::SignIns::CANCELLED)
    assert_nil @service.advance!(stale)
    assert_equal SubscriptionProxy::SignIns::CANCELLED, sign_in.reload.error
  end

  test "cancelling answers whether it was this request that ended the sign-in" do
    sign_in = start
    Client.any_instance.expects(:cancel_sign_in).once

    assert @service.cancel!(sign_in)
    assert_not @service.cancel!(sign_in)
  end

  test "handing back an address looks once and leaves the rest to the page, and a second hand back after it finished answers what came of it" do
    sign_in = start(state: "mine")
    Client.any_instance.stubs(:finish_sign_in)
    Client.any_instance.expects(:sign_in_status).once.returns(:waiting)

    assert_nil @service.hand_back!(sign_in, "http://localhost:1455/auth/callback?code=c&state=mine")

    sign_in.settle!(SubscriptionSignIn::STATUS_DONE)
    Client.any_instance.expects(:finish_sign_in).never
    outcome = @service.hand_back!(sign_in.reload, "http://localhost:1455/auth/callback?code=c&state=mine")
    assert_not outcome.fresh
  end

  test "nothing starts while the proxy is not usable" do
    SubscriptionProxy::Check.failed!("down")
    Client.any_instance.expects(:start_sign_in).never

    assert_raises(SubscriptionProxy::SignIns::Failed) { @service.start!("chatgpt") }
  end

  test "a device sign-in keeps its code, and Kimi signs in where the person chose" do
    Client.any_instance.expects(:start_sign_in).with("kimi", sign_in_id: instance_of(String))
          .returns(Client::SignIn.new(state: "kmi-1", url: "https://www.kimi.com/code/authorize_device?user_code=TCXU", user_code: "TCXU", expires_at: 30.minutes.from_now))

    sign_in = @service.start!("kimi", site: "kimi")

    assert_equal [ "kimi", "TCXU" ], [ sign_in.proxy, sign_in.user_code ]
  end
end
