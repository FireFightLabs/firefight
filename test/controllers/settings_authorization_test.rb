require "test_helper"

class SettingsAuthorizationTest < ActionDispatch::IntegrationTest
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_statuses, :incident_lifecycle_stages

  setup do
    @workspace = workspaces(:slack_workspace_one)
  end

  test "members are blocked from settings mutations across controllers" do
    sign_in(users(:bob), @workspace)
    source = @workspace.alert_sources.create!(name: "Guarded", provider: AlertSource::PROVIDER_GENERIC)

    attempts = [
      -> { post alert_sources_url, params: { alert_source: { name: "X" } } },
      -> { post token_alert_source_url(source) },
      -> { get sample_payload_alert_source_url(source) },
      -> { patch alert_routing_url, params: { policy: { enabled: false } } },
      -> { post alert_routing_send_test_url, params: { fields: {} }, as: :json },
      -> { post policy_rules_url, params: { rule: { conditions: [], outcome: {} } } },
      -> { post webhooks_url, params: { webhook: { url: "https://x.test" } } },
      -> { post incident_severities_url, params: { name: "Sev X" } },
      -> { post catalogue_types_url, params: { name: "Type X" } }
    ]

    attempts.each do |attempt|
      attempt.call
      assert_redirected_to dashboard_path, "expected member to be blocked: #{@request.path}"
    end
    assert_equal 0, @workspace.policies.count
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
