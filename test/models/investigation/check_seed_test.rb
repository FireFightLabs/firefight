require "test_helper"

class Investigation::CheckSeedTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @check = @workspace.investigation_checks.create!(name: "Cloud bill", kind: Investigation::Check::KIND_COST, cadence: Investigation::Check::CADENCE_WEEKLY,
                                                     hour: 9, weekday: 1, time_zone: "UTC", notes: "Our budget is $2,000 a month.")
    @run = @workspace.investigations.create!(subject: @check, trigger_source: Investigation::TRIGGER_SCHEDULE, max_turns: 10, max_spend_cents: 400)
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "aws", name: "AWS")
    @workspace.integrations.create!(kind: Integration::KIND_NATIVE, provider: "render", name: "Render")
  end

  test "a check run starts from the check, its skill and notes, what it raised before, and which providers report spend" do
    reading = Investigation::Notice::Reading.new(signal: Investigation::Notice::SIGNAL_COST, topic: "AWS bill", summary: "Up 40% on last month.",
                                                 severity: Investigation::Notice::SEVERITY_MEDIUM)
    Investigation::Notice.observe!(@workspace, reading, check: @check)

    pack = Investigation::CheckSeed.new(@run).gather

    assert_equal [ "Cloud bill", "cost_trends", "Our budget is $2,000 a month." ], pack["check"].values_at("name", "skill", "notes")
    assert_equal "AWS bill", pack["already_raised"].sole["topic"]
    assert_equal [ "aws_cost" ], pack["billing"]["skills"]
    assert_equal [ "Render" ], pack["billing"]["not_reported_by"]
  end

  test "a run's seed pack holds no clues, since a check has no symptom" do
    @run.build_seed_pack!

    assert_not @run.seed_pack.key?(Investigation::Seeding::KEY_CLUES)
    assert @run.seed_pack.key?("check")
  end
end
