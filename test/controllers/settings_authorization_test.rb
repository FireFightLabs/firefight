require "test_helper"

class SettingsAuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "members are blocked from settings mutations across controllers" do
    sign_in(users(:bob), @workspace)
    source = @workspace.alert_sources.create!(name: "Guarded", provider: AlertSource::PROVIDER_GENERIC)

    attempts = [
      -> { post alert_sources_url, params: { alert_source: { name: "X" } } },
      -> { post token_alert_source_url(source) },
      -> { patch alert_routing_url, params: { policy: { enabled: false } } },
      -> { post alert_routing_send_test_url, params: { fields: {} }, as: :json },
      -> { post policy_rules_url, params: { rule: { conditions: [], outcome: {} } } },
      -> { post webhooks_url, params: { webhook: { url: "https://x.test" } } },
      -> { get signing_secret_webhook_url(webhooks(:active_webhook)) },
      -> { post incident_severities_url, params: { name: "Sev X" } },
      -> { post catalogue_types_url, params: { name: "Type X" } }
    ]

    attempts.each do |attempt|
      attempt.call
      assert_redirected_to dashboard_path, "expected member to be blocked: #{@request.path}"
      assert_match "don't have permission", flash[:alert]
    end
    assert_equal 0, @workspace.policies.count
  end

  test "a refusal goes back to the page it came from" do
    sign_in(users(:bob), @workspace)

    post incident_severities_url, params: { name: "Sev X" }, headers: { "HTTP_REFERER" => settings_severities_url }

    assert_redirected_to settings_severities_url
    assert_equal "You don't have permission to change severities. Ask a workspace admin to grant you severities access in Settings, Permissions.", flash[:alert]
  end

  test "a grant opens a settings mutation to a member" do
    bob = workspace_memberships(:bob_workspace_one)
    @workspace.ability_grants.create!(
      principal: bob,
      action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_SEVERITIES, Ability::Action::ACTION_CREATE))
    )
    sign_in(users(:bob), @workspace)

    post incident_severities_url, params: { name: "Granted" }

    assert_redirected_to settings_severities_path
    assert @workspace.incident_severities.exists?(name: "Granted")
    assert @workspace.ability_invocations.exists?(
      principal: bob, action_key: "severities.create", decision: Ability::Invocation::DECISION_ALLOW,
      source: AbilityGateway::SOURCE_WEB, outcome: Ability::Invocation::OUTCOME_SUCCESS
    )
  end

  test "members are blocked from the admin-only surfaces" do
    sign_in(users(:bob), @workspace)

    [ settings_permissions_url, settings_activity_url ].each do |url|
      get url, headers: inertia_headers
      assert_redirected_to dashboard_path, "expected member to be blocked from #{url}"
    end
  end

  test "members read approvals and sample payloads like every other surface" do
    sign_in(users(:bob), @workspace)
    source = @workspace.alert_sources.create!(name: "Guarded", provider: AlertSource::PROVIDER_GENERIC)

    get settings_approvals_url, headers: inertia_headers
    assert_response :success

    get sample_payload_alert_source_url(source)
    assert_response :success
  end

  test "an admin-only resource cannot be granted" do
    bob = workspace_memberships(:bob_workspace_one)
    grant = @workspace.ability_grants.new(
      principal: bob,
      action: Ability::Action.system!(Ability::Action.system_key(Ability::Action::RESOURCE_PERMISSIONS, Ability::Action::ACTION_UPDATE))
    )

    assert_not grant.valid?
    assert_includes grant.errors.full_messages.to_sentence, "admin-only"
  end

  test "admins keep access to the governance surfaces" do
    sign_in(users(:alice), @workspace)

    [ settings_permissions_url, settings_activity_url, settings_approvals_url ].each do |url|
      get url, headers: inertia_headers
      assert_response :success, "expected admin to reach #{url}"
    end
  end

  test "members keep read access to settings pages and the route tester" do
    @workspace.policies.create!(domain: Policy::DOMAIN_ALERT_ROUTING, name: "Routing")
      .policy_rules.create!(priority: 1, conditions: [],
                            outcome: { "action" => AlertIngestService::ACTION_DROP })
    sign_in(users(:bob), @workspace)

    get settings_alert_sources_url, headers: inertia_headers
    assert_response :success

    post alert_routing_test_url, params: { fields: { service: "x" } }, as: :json
    assert_response :success
  end

  test "the webhooks page never carries a signing secret" do
    secret = webhooks(:active_webhook).signing_secret
    sign_in(users(:alice), @workspace)

    get settings_webhooks_url, headers: inertia_headers
    assert_response :success
    assert_not_includes response.body, secret,
                        "an admin's page props must not embed the secret either"
  end

  test "an admin fetches a signing secret only by asking for it" do
    sign_in(users(:alice), @workspace)

    get signing_secret_webhook_url(webhooks(:active_webhook))
    assert_response :success
    assert_equal webhooks(:active_webhook).signing_secret,
                 JSON.parse(response.body)["signingSecret"]
  end

  test "admins pass the same gates" do
    sign_in(users(:alice), @workspace)

    post alert_sources_url, params: { alert_source: { name: "Allowed" } }
    assert_redirected_to settings_alert_sources_path
    assert @workspace.alert_sources.exists?(name: "Allowed")
  end

  private

  include InertiaTestHelper

  def sign_in(user, workspace)
    ApplicationController.any_instance.stubs(:current_user).returns(user)
    ApplicationController.any_instance.stubs(:current_workspace).returns(workspace)
    ApplicationController.any_instance.stubs(:user_signed_in?).returns(true)
  end
end
