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

  def start(subscription = "chatgpt", state: "state-#{SecureRandom.hex(4)}", **)
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: state, url: "https://auth.openai.com/oauth/authorize?state=#{state}", user_code: nil, expires_at: nil))
    @service.start!(subscription, **)
  end

  test "a finished sign-in's one new credential is given this workspace's prefix and becomes its account" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json") ])
    Client.any_instance.expects(:claim).with("codex-ana.json", prefix: @workspace.id)

    outcome = @service.advance!(sign_in)

    account = outcome.account
    assert_equal [ AiProviders::KIND_SUBSCRIPTION, "chatgpt", "codex-ana.json", "ana@example.com" ], [ account.kind, account.provider, account.proxy_credential, account.credential_hint ]
    assert_equal [ "gpt-6.1-sol", "gpt-6-luna" ], [ account.model_for(WorkspaceAiAccount::MAIN), account.model_for(WorkspaceAiAccount::FAST) ]
    assert_equal SubscriptionSignIn::STATUS_DONE, sign_in.reload.status
    assert outcome.fresh
  end

  test "a credential another workspace holds is never claimed, and the same account signed in elsewhere is refused" do
    other = workspaces(:slack_workspace_two)
    add_subscription_account!(other, credential: "codex-ana.json")
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", created_at: 1.day.ago, updated_at: Time.current) ])
    Client.any_instance.expects(:claim).never

    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(sign_in) }

    assert_equal SubscriptionProxy::SignIns::TAKEN, error.message
    assert_empty @workspace.workspace_ai_accounts.subscriptions
  end

  test "signing the same account in again keeps its credential and clears what was wrong" do
    account = add_subscription_account!(@workspace, credential: "codex-ana.json", state: { "signed_out" => true })
    sign_in = start(account: account)
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json", created_at: 1.day.ago, updated_at: Time.current) ])

    outcome = @service.advance!(sign_in)

    assert outcome.reconnected
    assert_equal :verified, outcome.account.tap { |found| found.update_columns(verified_at: Time.current) }.state
  end

  test "two sign-ins of one kind finishing together are both refused rather than guessed at, and their credentials removed" do
    mine = start
    theirs = SubscriptionProxy::SignIns.new(workspaces(:slack_workspace_two), by: nil)
    Client.any_instance.stubs(:start_sign_in).returns(Client::SignIn.new(state: "theirs", url: "https://auth.openai.com", user_code: nil, expires_at: nil))
    rival = theirs.start!("chatgpt")
    Client.any_instance.stubs(:sign_in_status).returns(:done)
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json"), proxy_credential(name: "codex-ben.json", email: "ben@example.com") ])
    Client.any_instance.expects(:claim).never
    Client.any_instance.expects(:delete).twice

    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(mine) }

    assert_equal SubscriptionProxy::SignIns::AT_ONCE, error.message
    assert_equal SubscriptionSignIn::STATUS_FAILED, rival.reload.status
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
    Client.any_instance.stubs(:credentials).returns([ proxy_credential(name: "codex-ana.json") ])
    Client.any_instance.stubs(:claim)

    outcome = @service.hand_back!(sign_in, "http://localhost:1455/auth/callback?code=the-code&state=mine")

    assert_equal "codex-ana.json", outcome.account.proxy_credential
  end

  test "a sign-in still waiting says nothing, and one past its time is ended" do
    sign_in = start
    Client.any_instance.stubs(:sign_in_status).returns(:waiting)
    assert_nil @service.advance!(sign_in)

    sign_in.update_columns(expires_at: 1.minute.ago)
    error = assert_raises(SubscriptionProxy::SignIns::Failed) { @service.advance!(sign_in) }
    assert_equal SubscriptionProxy::SignIns::TIMED_OUT, error.message
  end

  test "nothing starts while the proxy is not usable" do
    SubscriptionProxy::Check.failed!("down")
    Client.any_instance.expects(:start_sign_in).never

    assert_raises(SubscriptionProxy::SignIns::Failed) { @service.start!("chatgpt") }
  end

  test "a device sign-in keeps its code, and Kimi signs in where the person chose" do
    Client.any_instance.expects(:start_sign_in).with("kimi").returns(Client::SignIn.new(state: "kmi-1", url: "https://www.kimi.com/code/authorize_device?user_code=TCXU", user_code: "TCXU", expires_at: 30.minutes.from_now))

    sign_in = @service.start!("kimi", site: "kimi")

    assert_equal [ "kimi", "TCXU" ], [ sign_in.proxy, sign_in.user_code ]
  end
end
