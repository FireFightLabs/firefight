require "test_helper"

class HalonOnCallControllerTest < ActionDispatch::IntegrationTest
  include OnCallTestHelper

  setup do
    alert_run_with_restart_fix
    sign_in(users(:alice), @workspace)
  end

  test "the page shows the settings, each rule with why it cannot act, and what on the map a rule can name" do
    rule = restart_rule

    get halon_on_call_url, headers: inertia_headers

    assert_equal "halon/on-call", JSON.parse(response.body)["component"]
    assert_equal false, inertia_props.dig("settings", "alertInvestigationsEnabled")
    shown = inertia_props["rules"].sole
    assert_equal [ rule.id, rule.sentence, 0 ], [ shown["id"], shown["sentence"], shown["usageCount"] ]
    assert_match "holds no grant", shown["blockedReason"]
    web = inertia_props["resources"].find { |resource| resource["id"] == @web.id }
    assert_equal %w[rollback restart], web["capabilities"]
  end

  test "saving the settings says so, and a ceiling out of range is refused with why" do
    patch halon_on_call_url, params: { alert_investigations_enabled: true, alert_storm_ceiling_cents: 2_500, on_call_paging_enabled: true }

    assert_redirected_to halon_on_call_path
    assert_equal "On-call settings were updated.", flash[:notice]
    assert_equal [ true, 2_500, true ], @workspace.reload.values_at(:alert_investigations_enabled, :alert_storm_ceiling_cents, :on_call_paging_enabled)

    patch halon_on_call_url, params: { alert_storm_ceiling_cents: 10 }
    assert_equal 2_500, @workspace.reload.alert_storm_ceiling_cents
  end

  test "a member may not change how Halon works on call" do
    sign_in(users(:bob), @workspace)

    patch halon_on_call_url, params: { alert_investigations_enabled: true }

    assert_not @workspace.reload.alert_investigations_enabled
  end
end
