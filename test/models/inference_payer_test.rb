require "test_helper"

class InferencePayerTest < ActiveSupport::TestCase
  ChargingBackend = Struct.new(:charged) do
    def check(_workspace, _feature) = Entitlements.allow
    def firefight_pays_for_ai?(_workspace) = false
    def ai_credit(_workspace) = AiAccountTestHelper::Credit.new(true, false)

    def charge_ai!(inference)
      charged << inference.id
      (inference.cost_micros * 1.2).round
    end
  end

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "a call no workspace chose a payer for is the deployment's, the operator's here and Firefight's on its cloud" do
    _, inference = Inference.track(workspace: @workspace, feature: "payer_test", provider: "openai", model: "gpt-4o") { llm_reply }
    assert_equal [ Inference::PAID_BY_OPERATOR, nil, nil ], [ inference.paid_by, inference.workspace_ai_account, inference.billed_micros ]

    on_firefights_cloud!(own: true)
    _, hosted = Inference.track(workspace: @workspace, feature: "payer_test", provider: "openai", model: "gpt-4o") { llm_reply }
    assert_equal Inference::PAID_BY_FIREFIGHT, hosted.paid_by
  end

  test "a call on the workspace's own account names it, and nothing is billed" do
    account = add_ai_account!(@workspace)
    choice = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)

    _, inference = Inference.track(workspace: @workspace, feature: "payer_test", **choice.ledger) { llm_reply(cost: 0.002) }

    assert_equal [ Inference::PAID_BY_ACCOUNT, account, nil ], [ inference.paid_by, inference.workspace_ai_account, inference.billed_micros ]
  end

  test "a call on Firefight credits is charged once by the hosted backend, which says what it billed" do
    backend = ChargingBackend.new([])
    Entitlements.backend = backend
    choice = FirefightAi.model_for(AiPurpose::SUMMARY, workspace: @workspace)
    assert_equal Inference::PAID_BY_CREDITS, choice.payer.paid_by

    _, inference = Inference.track(workspace: @workspace, feature: "payer_test", **choice.ledger) { llm_reply(cost: 0.01) }

    assert_equal [ inference.id ], backend.charged
    assert_equal 12_000, inference.reload.billed_micros
  end

  test "an install someone runs themselves charges nothing" do
    assert_nil Entitlements.charge_ai!(Inference.new)
  end
end
