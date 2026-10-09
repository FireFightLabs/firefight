require "test_helper"

class WorkspaceAiAccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @global = RubyLLM.config
    @saved = AiProviders.every_provider_option.index_with { |option| @global.public_send(option) }
  end

  teardown do
    @saved.each { |option, value| @global.public_send("#{option}=", value) }
  end

  # A RubyLLM context starts as a copy of the deployment's configuration. Without emptying it, a workspace's Anthropic
  # account would still carry Firefight's OpenAI key and Bedrock credentials, and a call on another provider would run
  # on Firefight's account.
  test "a workspace's context never holds Firefight's own keys, whatever the deployment configured" do
    deployment = {
      openai_api_key: "sk-firefight-openai", anthropic_api_key: "sk-firefight-anthropic", gemini_api_key: "firefight-gemini",
      openrouter_api_key: "sk-or-firefight", bedrock_api_key: "AKIAFIREFIGHT", bedrock_secret_key: "firefight-secret",
      bedrock_region: "us-east-1", bedrock_credential_provider: Object.new, vertexai_service_account_key: "{\"firefight\":true}",
      vertexai_project_id: "firefight-project", vertexai_location: "us-central1", openai_api_base: "https://firefight.internal/v1"
    }
    deployment.each { |option, value| @global.public_send("#{option}=", value) }
    account = add_ai_account!(@workspace, provider: "anthropic", key: "sk-ant-workspace")

    config = account.llm_context.config

    assert_equal "sk-ant-workspace", config.anthropic_api_key
    held = AiProviders.every_provider_option.reject { |option| option == :anthropic_api_key }.filter_map do |option|
      option if config.public_send(option).present?
    end
    assert_empty held, "every setting but the account's own is empty"
    deployment.each { |option, value| assert_equal value, @global.public_send(option), "the deployment's own configuration is left as it was" }
  end

  test "an account's settings reach only its own provider's options, and the request timeout is the deployment's" do
    account = add_ai_account!(@workspace, provider: "openai", key: "sk-own", settings: { "api_base" => "https://llm.example.com/v1",
                                                                                        "organization_id" => "org-1" })

    config = account.llm_context.config

    assert_equal [ "sk-own", "https://llm.example.com/v1", "org-1" ], [ config.openai_api_key, config.openai_api_base, config.openai_organization_id ]
    assert_equal FirefightAi.configuration.request_timeout, config.request_timeout
  end

  test "Bedrock needs its own access key and secret, so it never falls back to credentials the server holds" do
    account = @workspace.workspace_ai_accounts.new(provider: "bedrock", label: "Bedrock", kind: AiProviders::KIND_API_KEY, position: 1)
    account.assign_settings("region" => "us-east-1")
    account.assign_models("main" => "anthropic.claude-sonnet-4-5-20250929-v1:0", "fast" => "anthropic.claude-sonnet-4-5-20250929-v1:0")

    assert_not account.valid?
    assert_includes account.errors[:base], "Access key ID is required"
    assert_includes account.errors[:base], "Secret access key is required"

    account.assign_settings("api_key" => "AKIAOWN", "secret_key" => "own-secret")
    assert account.valid?, account.errors.full_messages.to_sentence
  end

  test "Vertex AI needs a service account key, so it never falls back to the machine's own Google credentials" do
    account = @workspace.workspace_ai_accounts.new(provider: "vertexai", label: "Vertex", kind: AiProviders::KIND_API_KEY, position: 1)
    account.assign_settings("project_id" => "acme", "location" => "us-central1")
    account.assign_models("main" => "claude-sonnet-4-5", "fast" => "claude-haiku-4-5")

    assert_not account.valid?
    assert_includes account.errors[:base], "Service account key (JSON) is required"
  end

  test "a key is write-only: an empty field keeps it, and only its last characters are shown" do
    account = add_ai_account!(@workspace, key: "sk-ant-secret-4f2a")
    assert_equal "API key ending in 4f2a. Enter a new one to replace it.", account.credential_summary

    account.assign_settings("api_key" => "")
    account.save!
    assert_equal "sk-ant-secret-4f2a", account.llm_context.config.anthropic_api_key

    account.assign_settings("api_key" => "sk-ant-new-9b1c")
    account.save!
    assert_equal [ "sk-ant-new-9b1c", "9b1c" ], [ account.reload.llm_context.config.anthropic_api_key, account.credential_hint ]
    assert_not_includes account.attributes.except("credentials").to_json, "sk-ant-new", "the key is only in the encrypted column"
  end

  test "a model Firefight cannot size cannot be Halon's main model, and the recommended ones are filled in" do
    account = @workspace.workspace_ai_accounts.new(provider: "anthropic", label: "Anthropic", kind: AiProviders::KIND_API_KEY)
    account.assign_models({})
    assert_equal [ "claude-sonnet-5", "claude-haiku-4-5" ], [ account.model_for(WorkspaceAiAccount::MAIN), account.model_for(WorkspaceAiAccount::FAST) ]

    account.assign_models("main" => "a-model-nobody-has")
    assert_not account.valid?
    assert account.errors[:"models.main"].any?

    account.assign_models("main" => "gpt-4o")
    assert_not account.valid?, "a model another provider lists is not one this provider serves"
    assert account.errors[:"models.main"].any?
  end

  test "a private or loopback address is refused where Firefight's network is not the customer's" do
    on_firefights_cloud!
    account = @workspace.workspace_ai_accounts.new(provider: "openai", label: "Proxy", kind: AiProviders::KIND_API_KEY, position: 1)
    account.assign_settings("api_key" => "sk-own", "api_base" => "http://169.254.169.254/v1")
    account.assign_models("main" => "gpt-4o", "fast" => "gpt-4o-mini")

    assert_not account.valid?
    assert_includes account.errors[:base], "The API base URL is on a private network, which Firefight does not reach"

    account.assign_settings("api_base" => "http://localhost:11434/v1")
    assert_not account.valid?

    Entitlements.reset_backend!
    assert account.valid?, "an install someone runs themselves may reach its own network"
  end

  test "a local provider is offered only where the network is the customer's own" do
    assert AiProviders.offered_to?(@workspace, "ollama")

    on_firefights_cloud!
    assert_not AiProviders.offered_to?(@workspace, "ollama")
    assert AiProviders.offered_to?(@workspace, "anthropic")
  end

  test "an account runs out of credit once, so of calls refused together only one tells the admins" do
    account = add_ai_account!(@workspace)
    first = WorkspaceAiAccount.find(account.id)
    second = WorkspaceAiAccount.find(account.id)

    assert_enqueued_jobs 1, only: WorkspaceAiAccountNoticeJob do
      threads = [ first, second ].map { |copy| Thread.new { AiRefusal.account_ran_out!(copy, FirefightAi::OutOfCredit.new("Your credit balance is too low")) } }
      assert_equal [ true, false ], threads.map(&:value).sort_by { |moved| moved ? 0 : 1 }
    end
    assert_equal :out_of_credit, account.reload.state
    assert_equal "The account has no credit left.", account.last_error
    assert_not WorkspaceAiAccount.usable.exists?(account.id)
  end

  test "the account only records that it stopped, and the admins are told by whoever handled the refusal" do
    account = add_ai_account!(@workspace)

    assert_no_enqueued_jobs { assert account.ran_out!(FirefightAi::OutOfCredit.new) }
    assert_enqueued_with(job: WorkspaceAiAccountNoticeJob, args: [ account.id, WorkspaceAiAccount::NOTICE_KEY_REFUSED ]) do
      assert AiRefusal.key_refused!(account, FirefightAi::TerminalError.new("bad key", reason: "UnauthorizedError"))
    end
  end

  test "an answered call puts the account back in use" do
    account = add_ai_account!(@workspace)
    account.key_refused!(FirefightAi::TerminalError.new("bad key", reason: "UnauthorizedError"))
    assert_equal [ :failing, "The provider refused the key." ], [ account.reload.state, account.last_error ]

    account.answered!

    assert_equal :unchecked, account.reload.state
    assert WorkspaceAiAccount.usable.exists?(account.id)
    assert_not_nil account.last_used_at
  end

  test "deleting one says what Halon uses after it, including when nothing is left" do
    account = add_ai_account!(@workspace)
    assert_equal "Halon will use the next account.", account.deletion_consequence, "the operator's keys come after it"

    on_firefights_cloud!
    assert_equal "Halon will have no AI account to use until an admin adds one.", account.deletion_consequence

    add_ai_account!(@workspace, label: "Second")
    assert_equal "Halon will use the next account.", account.deletion_consequence
  end

  test "a check the provider was too busy to answer leaves the account in use and says to check again" do
    account = add_ai_account!(@workspace)

    account.check_failed!(FirefightAi::TransientError.new("overloaded", reason: "OverloadedError"))

    assert_equal [ :unchecked, "The provider was busy and did not answer. Check again in a minute." ], [ account.state, account.last_error ]
    assert WorkspaceAiAccount.usable.exists?(account.id)
  end
end
