require "test_helper"

class AiFundingTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "the workspace's own accounts come first by position, skipping any switched off, out of credit or refused, then the operator's keys" do
    first = add_ai_account!(@workspace, label: "First")
    off = add_ai_account!(@workspace, label: "Off", enabled: false)
    dry = add_ai_account!(@workspace, label: "Dry", out_of_credit_since: 1.hour.ago)
    refused = add_ai_account!(@workspace, label: "Refused", failing_since: 1.hour.ago)
    second = add_ai_account!(@workspace, provider: "openai", key: "sk-own-openai", label: "Second")

    choices = AiFunding.for(@workspace, AiPurpose::INVESTIGATION)

    assert_equal [ first, second, nil ], choices.map { |choice| choice.payer.account }
    assert_equal [ Inference::PAID_BY_ACCOUNT, Inference::PAID_BY_ACCOUNT, Inference::PAID_BY_OPERATOR ], choices.map { |choice| choice.payer.paid_by }
    assert_equal [ "claude-sonnet-4-5", "gpt-4o" ], choices.first(2).map(&:model)
    assert_nil choices.last.context, "the operator's keys run on the deployment's own configuration"
    assert_not_includes choices.filter_map { |choice| choice.payer.account }, off
    assert_not_includes choices.filter_map { |choice| choice.payer.account }, dry
    assert_not_includes choices.filter_map { |choice| choice.payer.account }, refused
  end

  test "an account's quick model runs summaries, milestones and mention replies, and its main model the rest" do
    add_ai_account!(@workspace)

    assert_equal "claude-haiku-4-5", FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).model
    assert_equal "claude-haiku-4-5", FirefightAi.model_for(AiPurpose::INCIDENT_RESPONSE, workspace: @workspace).model
    assert_equal "claude-sonnet-4-5", FirefightAi.model_for(AiPurpose::POSTMORTEM, workspace: @workspace).model
    assert_equal "claude-sonnet-4-5", FirefightAi.model_for(AiPurpose::CODE_FIX, workspace: @workspace).model
  end

  test "Firefight's own workspaces keep Firefight's key after their own accounts" do
    on_firefights_cloud!(own: true)

    assert_equal Inference::PAID_BY_FIREFIGHT, FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @workspace).payer.paid_by
  end

  test "on Firefight's cloud a workspace pays with its credits while they can pay, and with nothing after" do
    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(true, false))
    assert_equal Inference::PAID_BY_CREDITS, FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace).payer.paid_by

    on_firefights_cloud!(credit: AiAccountTestHelper::Credit.new(false, true))
    choice = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)
    assert choice.unpaid?, "nobody pays, so no call is made"
    assert_raises(FirefightAi::OutOfCredit) { FirefightAi.generate(choice, purpose: AiPurpose::SUMMARY, inference: { workspace: @workspace }) { flunk } }
  end

  test "embeddings stay on the deployment's model and account whoever pays for the rest" do
    add_ai_account!(@workspace)

    assert_equal FirefightAi.deployment_model_for(AiPurpose::EMBEDDING).model, FirefightAi.embedding_model
  end

  test "a rehearsal is Firefight measuring Halon, so it never runs on the workspace's own account" do
    add_ai_account!(@workspace)
    incident = incidents(:active_critical_ws1)
    rehearsal = @workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_REHEARSAL, rehearsal: true,
                                                  max_turns: 4, max_spend_cents: 400)
    run = @workspace.investigations.create!(subject: incident, trigger_source: Investigation::TRIGGER_COMMAND, max_turns: 4, max_spend_cents: 400)

    assert_nil rehearsal.ai_model.payer, "the deployment's own account pays"
    assert_equal Inference::PAID_BY_ACCOUNT, run.ai_model.payer.paid_by
  end
end
