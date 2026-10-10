require "test_helper"

# An on-call run an alert starts and a scheduled monitoring check read the handbook as a chat or an investigation does.
class Investigation::HandbookFactsTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @on_call = handbook_page!(@workspace, "On call", "Page the platform on-call for anything in the cluster.")
  end

  test "a run an alert started reads the handbook among its starting facts" do
    run = @workspace.investigations.create!(subject: incidents(:active_critical_ws1), trigger_source: Investigation::TRIGGER_ALERT, max_turns: 10,
                                            max_spend_cents: 400)
    run.build_seed_pack!

    assert_equal [ @on_call.halon_line ], run.starting_facts[Investigation::Seeding::KEY_HANDBOOK]
  end

  test "a scheduled check reads the handbook among its starting facts, and its prompt says how to follow it" do
    check = @workspace.investigation_checks.create!(name: "Cloud bill", kind: Investigation::Check::KIND_COST, cadence: Investigation::Check::CADENCE_WEEKLY,
                                                    hour: 9, weekday: 1, time_zone: "UTC")
    run = @workspace.investigations.create!(subject: check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400)
    run.build_seed_pack!

    assert_equal [ @on_call.halon_line ], run.starting_facts[Investigation::Seeding::KEY_HANDBOOK]
    assert_includes FirefightAi::Monitor.system_prompt, FirefightAi::MemoryRule::HANDBOOK_RULE
  end
end
