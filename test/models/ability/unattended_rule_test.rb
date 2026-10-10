require "test_helper"

class Ability::UnattendedRuleTest < ActiveSupport::TestCase
  include OnCallTestHelper

  setup { alert_run_with_restart_fix }

  test "reads as the team would say it, and names the change in a few words" do
    rule = restart_rule(threshold: 2.5, minutes: 15)

    assert_equal "Restart web when the average of its 5xx responses over the last 15 minutes is above 2.5.", rule.sentence
    assert_equal "restart web", rule.change_words
    assert_equal "50", restart_rule.shown_threshold
  end

  test "every metric a capability reads has words a person reads" do
    assert_equal Integrations::Capabilities::METRIC_NAMES.sort, Ability::UnattendedRule::METRIC_LABELS.keys.sort
  end

  test "says why it cannot act: no grant of the tool, or the resource gone from the map" do
    rule = restart_rule

    assert_equal "Firefight Investigator holds no grant of Northflank's api_request, so this rule cannot act yet. Grant it under Gateway, Permissions.",
                 rule.blocked_reason
    grant_investigator(@api)
    assert_nil rule.reload.blocked_reason

    @web.update!(removed_at: Time.current)
    assert_equal "web is no longer on the resource map, so this rule cannot act.", rule.reload.blocked_reason
  end

  test "covers only a step that makes its change on its resource" do
    rule = restart_rule
    step = @plan.steps.sole

    assert rule.covers?(step)
    assert_not restart_rule(capability: Integrations::Capabilities::ROLLBACK).covers?(step)
    other = ResourceMap::Resource.create!(workspace: @workspace, provider: "northflank", account: "team/prod", kind: ResourceMap::KIND_SERVICE,
                                          external_id: "api-id", name: "api", integration_environment: @row, first_seen_at: Time.current, last_seen_at: Time.current)
    assert_not restart_rule(resource: other).covers?(step)
  end

  test "stays for the record once Halon acted under it, and counts that in one query" do
    rule = restart_rule
    assert_nil rule.delete_blocked_reason

    @plan.steps.sole.update!(applied_under_rule: rule)
    counted = @workspace.unattended_rules.with_usage_counts.find(rule.id)

    assert_equal 1, counted.usage_count
    assert_equal "Halon acted under this rule 1 time, so it stays for the record. Turn it off instead.", counted.delete_blocked_reason
  end

  test "refuses a capability it does not allow, a metric nothing reads, and a resource from another workspace" do
    rule = @workspace.unattended_rules.new(resource: @web, capability: Integrations::Capabilities::SCALE, metric: "happiness", threshold: -1, minutes: 0)

    assert_not rule.valid?
    assert_equal %i[capability metric threshold minutes].sort, rule.errors.attribute_names.sort
    elsewhere = workspaces(:slack_workspace_two).unattended_rules.new(resource: @web, capability: Integrations::Capabilities::RESTART,
                                                                      metric: "cpu", threshold: 1, minutes: 5)
    assert_not elsewhere.valid?
    assert_includes elsewhere.errors[:resource], "must be on this workspace's resource map"
  end

  test "offers what a connection holding it can restart or roll back" do
    choice = Ability::UnattendedRule.resource_choices(@workspace).find { |each| each.resource.id == @web.id }

    assert_equal %w[rollback restart], choice.capabilities
  end

  test "a fresh reading takes the highest average among the metric's series, and says when there is none" do
    rule = restart_rule
    Integrations::NativeExecutor.stubs(:call).returns(metrics_answer([ 10, 30 ], [ 60, 80 ]))

    reading = rule.read!(incident: @incident)

    assert reading.above?
    assert_equal "Halon read web just now. The average of its 5xx responses over the last 10 minutes was 70 on web-1, above 50.", reading.words
    Integrations::NativeExecutor.stubs(:call).returns(metrics_answer([]))
    error = assert_raises(Ability::UnattendedRule::Reading::Unread) { rule.read! }
    assert_equal "web has no 5xx responses in the last 10 minutes, so nothing shows it is above 50.", error.message
  end
end
