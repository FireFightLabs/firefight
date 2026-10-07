require "test_helper"

class AiAccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
    sign_in(users(:alice), @workspace)
  end

  test "an admin adds an account, which is checked with one call and confirmed with a toast" do
    FirefightAi.expects(:check_account).once.with { |choice, workspace:| choice.payer.account.provider == "anthropic" && workspace == @workspace }

    post ai_accounts_path, params: { provider: "anthropic", label: "Our Anthropic", settings: { api_key: "sk-ant-ours-4f2a" },
                                     models: { main: "claude-sonnet-4-5", fast: "claude-haiku-4-5" } }

    assert_redirected_to settings_workspace_path
    assert_equal "Our Anthropic was added and works.", flash[:notice]
    account = @workspace.workspace_ai_accounts.find_by!(label: "Our Anthropic")
    assert_equal [ "4f2a", 1 ], [ account.credential_hint, account.position ]
  end

  test "a save whose check fails is kept, out of Halon's way, and says why in plain words" do
    FirefightAi.stubs(:check_account).raises(FirefightAi::TerminalError.new("401 invalid x-api-key sk-ant-abc", reason: "UnauthorizedError"))

    post ai_accounts_path, params: { provider: "anthropic", label: "Typo", settings: { api_key: "sk-ant-typo" },
                                     models: { main: "claude-sonnet-4-5", fast: "claude-haiku-4-5" } }

    assert_equal "Typo was added, but the check failed. The provider refused the key. Halon will skip it until a check passes.", flash[:alert]
    account = @workspace.workspace_ai_accounts.find_by!(label: "Typo")
    assert_equal :failing, account.state
    assert_not WorkspaceAiAccount.usable.exists?(account.id)
  end

  test "a missing key is refused with what is missing, and nothing is saved" do
    post ai_accounts_path, params: { provider: "anthropic", label: "No key", settings: {}, models: {} }

    assert_empty @workspace.workspace_ai_accounts.where(label: "No key")
  end

  test "editing keeps the stored key when the field is left empty, and checks again" do
    account = add_ai_account!(@workspace, key: "sk-ant-kept")
    FirefightAi.stubs(:check_account).returns(nil)

    patch ai_account_path(account), params: { label: "Renamed", settings: { api_key: "" }, models: { main: "claude-sonnet-4" } }

    assert_equal "Renamed was updated and works.", flash[:notice]
    account.reload
    assert_equal [ "Renamed", "sk-ant-kept", "claude-sonnet-4" ], [ account.label, account.llm_context.config.anthropic_api_key, account.model_for(WorkspaceAiAccount::MAIN) ]
    assert_not_nil account.verified_at
  end

  test "turning one off and on, reordering and deleting each confirm themselves" do
    first = add_ai_account!(@workspace, label: "First")
    second = add_ai_account!(@workspace, label: "Second")

    patch disable_ai_account_path(first)
    assert_equal "First was turned off. Halon will skip it.", flash[:notice]
    assert_not first.reload.enabled

    patch enable_ai_account_path(first)
    assert_equal "First was turned on.", flash[:notice]

    patch reorder_ai_accounts_path, params: { ordered_ids: [ second.id, first.id ] }
    assert_equal "AI account order updated.", flash[:notice]
    assert_equal [ second, first ], @workspace.workspace_ai_accounts.reload.to_a

    delete ai_account_path(second)
    assert_equal "Second was deleted.", flash[:notice]
    delete ai_account_path(first)
    assert_empty @workspace.workspace_ai_accounts.reload, "the last one can go too"
  end

  test "checking again puts a fixed account back in use" do
    account = add_ai_account!(@workspace, failing_since: 1.hour.ago, last_error: "The provider refused the key.")
    FirefightAi.stubs(:check_account).returns(nil)

    post check_ai_account_path(account)

    assert_equal "#{account.label} was checked and works.", flash[:notice]
    assert_equal :verified, account.reload.state
  end

  test "only admins manage AI accounts" do
    sign_in(users(:bob), @workspace)

    post ai_accounts_path, params: { provider: "anthropic", label: "Member's", settings: { api_key: "sk-ant-x" }, models: {} }

    assert_match "You don't have permission to change ai accounts", flash[:alert]
    assert_empty @workspace.workspace_ai_accounts
  end

  # The test cache keeps nothing, so the count the limiter reads is stood in for.
  test "saves and checks are limited per workspace" do
    account = add_ai_account!(@workspace)
    FirefightAi.expects(:check_account).never
    counted = []
    ActiveSupport::Cache::NullStore.any_instance.stubs(:increment).with { |key, *| counted << key }
                                   .returns(AiAccountsController::CHECKS_PER_MINUTE + 1)

    post check_ai_account_path(account)

    assert_equal AiAccountsController::TOO_MANY, flash[:alert]
    assert(counted.any? { |key| key.include?(@workspace.id) })
  end

  test "the page lists accounts and providers, and never a key" do
    add_ai_account!(@workspace, key: "sk-ant-never-shown-4f2a", settings: { "api_base" => "https://llm.example.com/v1" })

    get settings_workspace_path, headers: inertia_headers

    account = inertia_props.fetch("aiAccounts").sole
    assert_equal [ "Anthropic", "https://llm.example.com/v1", "API key ending in 4f2a. Enter a new one to replace it." ],
                 [ account["providerName"], account.dig("settings", "api_base"), account["keySummary"] ]
    assert_not_includes response.body, "sk-ant-never-shown"
    assert_includes inertia_props.fetch("aiProviders").map { |provider| provider["slug"] }, "ollama"
    assert_nil inertia_props["aiCredits"], "credits are only sold on Firefight's cloud"
    assert_nil inertia_props["aiSignIn"], "Sign in with ChatGPT waits for its flag"
  end
end
