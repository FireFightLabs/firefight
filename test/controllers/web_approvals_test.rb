require "test_helper"

class WebApprovalsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @bob = workspace_memberships(:bob_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)

    policy = @workspace.policies.create!(domain: Policy::DOMAIN_APPROVALS, name: "Approvals")
    policy.policy_rules.create!(
      priority: 1,
      conditions: [ { field: "risk_level", operator: PolicyRule::OPERATOR_IS_ONE_OF, value: [ Ability::Action::RISK_WRITE, Ability::Action::RISK_DESTRUCTIVE ] } ],
      outcome: { "require" => { "role" => WorkspaceMembership.roles[:admin], "count" => 1 } }
    )
    [ Ability::Action::ACTION_CREATE, Ability::Action::ACTION_DELETE ].each do |crud_action|
      @workspace.ability_grants.create!(
        principal: @bob,
        action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_SEVERITIES, crud_action))
      )
    end
    sign_in(users(:bob), @workspace)
  end

  test "a matching policy parks the request and sends the person back with a notice" do
    assert_no_difference "IncidentSeverity.count" do
      post incident_severities_url, params: { name: "Parked", color: "#123456" },
                                    headers: { "HTTP_REFERER" => settings_severities_url }
    end

    assert_redirected_to settings_severities_url
    assert_match "needs a workspace admin to approve", flash[:notice]

    approval = @workspace.ability_approvals.find_by!(action_key: "severities.create")
    assert approval.pending?
    assert_equal AbilityGateway::SOURCE_WEB, approval.source
    assert_equal ApprovalResumption::KIND_WEB, approval.resume_payload["kind"]
    assert_equal "/app/settings/severities", approval.resume_payload["path"]
    assert_equal "POST", approval.resume_payload["method"]
    assert_includes approval.resume_payload["body"], "name=Parked"
    assert_equal "application/x-www-form-urlencoded", approval.resume_payload["content_type"]
    assert_equal @bob.id, approval.resume_payload["membership_id"]
    assert_equal "/app/settings/severities", approval.params["path"]
    assert @workspace.ability_invocations.exists?(action_key: "severities.create", decision: Ability::Invocation::DECISION_PENDING, source: AbilityGateway::SOURCE_WEB)
  end

  test "approving replays the request as the requester and tells them by direct message" do
    post incident_severities_url, params: { name: "Parked", color: "#123456" }
    approval = @workspace.ability_approvals.find_by!(action_key: "severities.create")
    ApplicationController.any_instance.unstub(:current_user)
    ApplicationController.any_instance.unstub(:current_workspace)
    ApplicationController.any_instance.unstub(:user_signed_in?)

    Slack::Client.expects(:post_message)
                 .with(has_entries(channel: @bob.platform_user_id, text: regexp_matches(/approved your request\. Parked was created\./)))
                 .returns({ ok: true })

    perform_enqueued_jobs do
      approval.approve!(by: @alice)
    end

    severity = @workspace.incident_severities.find_by!(name: "Parked")
    assert_equal "#123456", severity.color
    assert approval.reload.consumed_at.present?
    assert @workspace.ability_invocations.exists?(
      principal: @bob, action_key: "severities.create", decision: Ability::Invocation::DECISION_ALLOW,
      approval_id: approval.id, outcome: Ability::Invocation::OUTCOME_SUCCESS, source: AbilityGateway::SOURCE_WEB
    )
  end

  test "a replay whose guard refuses reports the guard's own reason" do
    severity = incident_severities(:critical_ws1)
    delete incident_severity_url(severity)
    approval = @workspace.ability_approvals.find_by!(action_key: "severities.delete")
    ApplicationController.any_instance.unstub(:current_user)
    ApplicationController.any_instance.unstub(:current_workspace)
    ApplicationController.any_instance.unstub(:user_signed_in?)

    Slack::Client.expects(:post_message)
                 .with(has_entries(channel: @bob.platform_user_id, text: regexp_matches(/couldn't finish it\. #{Regexp.escape(severity.deletion_blocked_reason)}/)))
                 .returns({ ok: true })

    perform_enqueued_jobs do
      approval.approve!(by: @alice)
    end

    assert IncidentSeverity.exists?(severity.id)
  end

  test "declining tells the requester nothing changed" do
    post incident_severities_url, params: { name: "Parked", color: "#123456" }
    approval = @workspace.ability_approvals.find_by!(action_key: "severities.create")

    Slack::Client.expects(:post_message)
                 .with(has_entries(channel: @bob.platform_user_id, text: regexp_matches(/declined your request/)))
                 .returns({ ok: true })

    perform_enqueued_jobs do
      approval.deny!(by: @alice)
    end

    assert_not @workspace.incident_severities.exists?(name: "Parked")
  end

  test "a person editing an incident is not ledgered, a person changing configuration is" do
    @workspace.policies.destroy_all
    sign_in(users(:alice), @workspace)
    incident = incidents(:active_critical_ws1)

    assert_no_difference "Ability::Invocation.count" do
      patch incident_postmortem_status_url(incident), params: { status: "draft" }
    end

    assert_difference "Ability::Invocation.count", 1 do
      post incident_severities_url, params: { name: "Audited", color: "#123456" }
    end
    invocation = @workspace.ability_invocations.find_by!(action_key: "severities.create")
    assert_equal AbilityGateway::SOURCE_WEB, invocation.source
    assert_equal @alice, invocation.principal
  end
end
