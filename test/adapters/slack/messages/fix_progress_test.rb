require "test_helper"

class Slack::Messages::FixProgressTest < ActiveSupport::TestCase
  include FixPlanTestHelper

  PULL = "https://github.com/FireFightLabs/firefight/pull/856".freeze

  setup do
    @plan = build_fix_plan(workspaces(:slack_workspace_one))
    @alice = workspace_memberships(:alice_workspace_one)
  end

  test "the fix is a checklist named for its incident, its steps by their short names, and never the instructions or a tool's words" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete, = @plan.steps.to_a
    delete.update_columns(title: "Delete the WAF rule")
    delete.move!(from: Investigation::RemediationStep::STATUS_PROPOSED, to: Investigation::RemediationStep::STATUS_RUNNING)
    delete.finish!(Investigation::RemediationStep::STATUS_DONE, result: "<!channel> deleted rule 123 from zone abc")

    blocks = Slack::Messages::FixProgress.build(@plan.reload)
    plan_block = blocks.first

    assert_equal [ "plan", "Fix for INC-001" ], plan_block.values_at(:type, :title)
    assert_equal [ [ "1. Delete the WAF rule", "complete" ], [ "2. A step for a person", "pending" ], [ "3. Open a pull request with the change", "pending" ] ],
                 plan_block[:tasks].map { |task| task.values_at(:title, :status) }
    assert_not_includes blocks.to_json, "deleted rule 123"
    assert_not_includes blocks.to_json, "dns.tf"
    assert_equal "Applying the fix: 1 of 3 steps done", Slack::Messages::FixProgress.fallback(@plan)
  end

  test "how the fix stands is one line under the checklist, which a message draws as a section since Slack keeps alerts to modals" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    assert_equal ":information_source:  Applying the fix  ·  0 of 3 steps done", state_line(@plan)

    @plan.steps.each { |step| step.update_columns(status: Investigation::RemediationStep::STATUS_DONE) }
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_APPLIED)
    assert_equal ":white_check_mark:  Fix applied  ·  3 of 3 steps done", state_line(@plan.reload)

    @plan.steps.third.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_SANDBOX)
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)
    assert_equal ":x:  Fix stopped: 1 of 3 steps failed  ·  2 of 3 steps done", state_line(@plan.reload)
    assert_equal "Fix stopped: 1 of 3 steps failed: 2 of 3 steps done", Slack::Messages::FixProgress.fallback(@plan)
    assert_not Slack::Messages::FixProgress.build(@plan).any? { |block| block[:type] == "alert" }
  end

  test "a step waiting on a person never looks like work under way, and says who it waits on" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    waiting, done, declined = @plan.steps.to_a
    waiting.update_columns(status: Investigation::RemediationStep::STATUS_WAITING_APPROVAL)
    done.update_columns(status: Investigation::RemediationStep::STATUS_DONE, done_by_id: @alice.id)
    declined.update_columns(status: Investigation::RemediationStep::STATUS_DECLINED, failure: "Bob declined it")

    tasks = Slack::Messages::FixProgress.build(@plan.reload).first[:tasks]

    assert_equal %w[pending complete error], tasks.pluck(:status)
    assert_equal [ "Waiting for approval before it runs.", "Done by Alice Smith", "Couldn't open a pull request with the change: Bob declined it." ],
                 tasks.map { |task| (task[:details] || task[:output]).dig(:elements, 0, :elements, 0, :text) }
  end

  test "a failed step is a card saying why in plain words with Try again, which asks first and names who it runs as" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    code = @plan.steps.third
    code.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, result: "Integrations::Unavailable: docker exited 125",
                        failure: Investigation::RemediationStep::FAILURE_SANDBOX)
    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)

    blocks = Slack::Messages::FixProgress.build(@plan.reload)
    card = card_with(blocks, Identifiers::FIX_STEP_RETRY)
    button = card[:actions].sole

    assert_equal [ ":x:  Couldn't open a pull request with the change: the code sandbox didn't start.", "Step 3" ], [ card.dig(:title, :text), card.dig(:subtitle, :text) ]
    assert_equal "Couldn't open a pull request with the change: the code sandbox didn't start.", blocks.first[:tasks].third.dig(:output, :elements, 0, :elements, 0, :text)
    assert_equal [ code.id, "Try step 3 again?" ], [ button[:value], button.dig(:confirm, :title, :text) ]
    assert_includes button.dig(:confirm, :text, :text), "as Alice Smith"
    assert_not_includes blocks.to_json, "docker exited"
  end

  test "a cancelled fix and one Halon applied under a rule offer no Try again" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_TOOL_SAID)
    @plan.cancel!(by: workspace_memberships(:bob_workspace_one))

    assert_nil card_with(Slack::Messages::FixProgress.build(@plan.reload), Identifiers::FIX_STEP_RETRY)

    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED, applied_from: AbilityGateway::SOURCE_INVESTIGATION)
    assert_nil card_with(Slack::Messages::FixProgress.build(@plan.reload), Identifiers::FIX_STEP_RETRY)
  end

  test "a code change at work says how far it got in counts, never the files or commands its agent named" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    code = @plan.steps.third
    work = Chat::CodeFixProgress.start
    work.add("Edited app/models/rule.rb")
    work.changed!("app/models/rule.rb")
    code.update!(status: Investigation::RemediationStep::STATUS_RUNNING, progress: work.to_json)

    task = Slack::Messages::FixProgress.build(@plan.reload).first[:tasks].third

    assert_equal [ "in_progress", "Writing the change: 1 step, 1 file changed so far" ], [ task[:status], task.dig(:details, :elements, 0, :elements, 0, :text) ]
    assert_not_includes task.to_json, "rule.rb"
  end

  test "a person's step is a card saying plainly it is theirs, naming who and where, with Done" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete, tell, = @plan.steps.to_a
    delete.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    tell.update_columns(title: "Invite Uros Nikolic to #inc-003 with <!channel>")

    blocks = Slack::Messages::FixProgress.build(@plan.reload)
    card = card_with(blocks, Identifiers::MARK_FIX_STEP_DONE)

    assert_equal "*Your step:* Invite Uros Nikolic to #inc-003 with &lt;!channel&gt;. Then press Done.", card.dig(:body, :text)
    assert_equal [ tell.id, "Done", "primary" ], card[:actions].sole.values_at(:value, :text, :style).then { |value, text, style| [ value, text[:text], style ] }
    assert_equal "Your step. Press Done once it is done.", blocks.first[:tasks].second.dig(:details, :elements, 0, :elements, 0, :text)
  end

  test "a step that went through shows what it produced as a visible link, and one already done says why" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete, _tell, code = @plan.steps.to_a
    delete.update_columns(status: Investigation::RemediationStep::STATUS_RUNNING)
    delete.finish!(Investigation::RemediationStep::STATUS_DONE, result: "Uros Nikolic is already in #inc-003.", already_done: "Uros Nikolic is already in #inc-003")
    code.update_columns(status: Investigation::RemediationStep::STATUS_RUNNING)
    code.finish!(Investigation::RemediationStep::STATUS_DONE, result: "Opened #{PULL} on FireFightLabs/firefight against main.")

    blocks = Slack::Messages::FixProgress.build(@plan.reload)
    tasks = blocks.first[:tasks]

    assert_equal [ { type: "text", text: "Already done: Uros Nikolic is already in #inc-003" } ], tasks.first.dig(:output, :elements, 0, :elements)
    assert_equal [ { type: "text", text: "Opened a pull request: " }, { type: "link", url: PULL, text: "PR #856" } ], tasks.third.dig(:output, :elements, 0, :elements)
    summary = blocks.second.dig(:elements, 0, :text)
    assert_includes summary, ":white_check_mark: 1. Make the change through a connected tool  _Already done: Uros Nikolic is already in #inc-003_"
    assert_includes summary, ":white_check_mark: 3. Open a pull request with the change  _Opened a pull request: <#{PULL}|PR #856>_"

    plain = Slack::Messages::FixProgress.build(@plan, rich: false).third.dig(:text, :text)
    assert_includes plain, "_Opened a pull request: <#{PULL}|PR #856>_"
  end

  test "a plan Slack shows folded still reads in full: a line under it lists each step and how it went" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_TOOL_SAID)

    summary = Slack::Messages::FixProgress.build(@plan.reload).second

    assert_equal "context", summary[:type]
    assert_equal ":x: 1. Make the change through a connected tool  _Couldn't make the change through a connected tool: the tool reported an error._\n" \
                 ":white_circle: 2. A step for a person\n:white_circle: 3. Open a pull request with the change  _Your step. Press Done once it is done._",
                 summary.dig(:elements, 0, :text)
  end

  test "a workspace without the newer blocks gets the same checklist, state and cards as plain blocks" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_FAILED, failure: Investigation::RemediationStep::FAILURE_TOOL_SAID)

    blocks = Slack::Messages::FixProgress.build(@plan.reload, rich: false)

    assert_equal [ ":hammer_and_wrench:  *Fix for INC-001*", "divider" ], [ blocks.first.dig(:text, :text), blocks.second[:type] ]
    assert_equal ":x: 1. Make the change through a connected tool  _Couldn't make the change through a connected tool: the tool reported an error._\n" \
                 ":white_circle: 2. A step for a person\n:white_circle: 3. Open a pull request with the change  _Your step. Press Done once it is done._",
                 blocks.third.dig(:text, :text)
    assert_equal ":information_source:  Applying the fix  ·  0 of 3 steps done", blocks.fourth.dig(:text, :text)
    assert_empty blocks.select { |block| %w[plan card alert].include?(block[:type]) }
    assert(blocks.any? { |block| block[:type] == "actions" && block[:elements].any? { |button| button[:action_id] == Identifiers::FIX_STEP_RETRY } })
  end

  test "a fix with more steps to act on than Slack takes sends the rest to the run page and stays inside fifty blocks" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    60.times do |index|
      @plan.steps.create!(position: index + 4, kind: Investigation::RemediationStep::KIND_MANUAL, description: "Check #{index}",
                          status: Investigation::RemediationStep::STATUS_APPROVED)
    end

    blocks = Slack::Messages::FixProgress.build(@plan.reload)

    assert_operator blocks.size, :<=, 50
    assert_match(/more steps to act on, on the run page/, blocks.last.dig(:body, :text))
  end

  test "a fix that ended offers Undo fix, which asks first, and one still applying or already undone does not" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    assert_nil undo_button(@plan)

    @plan.update_columns(status: Investigation::RemediationPlan::STATUS_PARTLY_APPLIED)
    @plan.steps.first.update_columns(status: Investigation::RemediationStep::STATUS_DONE)
    Entitlements.stubs(:check).returns(stub(blocked?: false))
    FirefightAi.stubs(:context_window).returns(200_000)
    button = undo_button(@plan.reload)
    assert_equal [ Identifiers::UNDO_FIX, @plan.id, "Write the undo?" ], [ button[:action_id], button[:value], button.dig(:confirm, :title, :text) ]

    undo = @plan.propose_undo!("summary" => "Put it back", "steps" => [ { "kind" => "manual", "title" => "Re-add the rule", "description" => "Re-add the rule" } ])
    assert_nil undo_button(@plan.reload)
    written = Slack::Messages::InvestigationRun.undo(plan: undo)
    assert_equal [ ":leftwards_arrow_with_hook:  *How to undo it*", "divider" ], [ written.first.dig(:text, :text), written.second[:type] ]
    undo.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    built = Slack::Messages::FixProgress.build(undo.reload)
    assert_equal [ "Undo for INC-001", ":information_source:  Undoing the fix  ·  0 of 1 steps done" ], [ built.first[:title], built.third.dig(:text, :text) ]
  end

  test "a fix being applied offers Cancel, which asks first, and a cancelled one says who stopped it" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    cancel = buttons(@plan).find { |element| element[:action_id] == Identifiers::CANCEL_FIX }
    assert_equal [ "Cancel fix", "Cancel this fix?" ], [ cancel.dig(:text, :text), cancel.dig(:confirm, :title, :text) ]

    @plan.cancel!(by: workspace_memberships(:bob_workspace_one))
    blocks = Slack::Messages::FixProgress.build(@plan)
    assert_equal ":warning:  Fix cancelled  ·  0 of 3 steps done", blocks.third.dig(:text, :text)
    assert blocks.last.dig(:body, :text).start_with?("Cancelled by Bob")
  end

  test "an approved step is a card that asks to be run, with how things stand now, Run and Dismiss, and Ask again once its approval expired" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    delete = @plan.steps.first
    approval = @plan.finding.investigation.workspace.ability_approvals.create!(
      principal: @alice, principal_label: "Alice", action_key: "cloudflare.execute", request_digest: "d", required_role: "admin",
      status: Ability::Approval::STATUS_APPROVED, approver: @alice, held_for_run: true, run_expires_at: 1.hour.from_now
    )
    delete.update_columns(status: Investigation::RemediationStep::STATUS_APPROVED, approval_id: approval.id)

    checking = card_with(Slack::Messages::FixProgress.build(@plan.reload), Identifiers::FIX_STEP_DISMISS)
    assert_includes checking.dig(:subtitle, :text), "Halon is checking how things stand now"
    assert_equal [ Identifiers::FIX_STEP_DISMISS ], checking[:actions].pluck(:action_id)

    delete.reload.checked!(Chat::CurrentState::Report.new(state: "The rule is gone already.", change: Chat::CurrentState::DONE_ALREADY))
    blocks = Slack::Messages::FixProgress.build(@plan.reload)
    ready = card_with(blocks, Identifiers::FIX_STEP_RUN)
    assert_equal [ "pending", "Alice Smith approved it. Waiting for Alice Smith to run it." ],
                 [ blocks.first[:tasks].first[:status], blocks.first[:tasks].first.dig(:details, :elements, 0, :elements, 0, :text) ]
    assert_equal [ "1. Make the change through a connected tool", "Alice Smith approved it. Run this step?" ], [ ready.dig(:title, :text), ready.dig(:subtitle, :text) ]
    assert ready.dig(:body, :text).start_with?("*Now:* The rule is gone already.\n:warning: This looks done already.")
    assert_equal [ Identifiers::FIX_STEP_RUN, Identifiers::FIX_STEP_DISMISS ], ready[:actions].pluck(:action_id)

    approval.update_columns(status: Ability::Approval::STATUS_EXPIRED)
    expired = card_with(Slack::Messages::FixProgress.build(@plan.reload), Identifiers::FIX_STEP_ASK_AGAIN)
    assert_includes expired.dig(:subtitle, :text), "nobody ran it within the hour"
    assert_equal [ Identifiers::FIX_STEP_ASK_AGAIN, Identifiers::FIX_STEP_DISMISS ], expired[:actions].pluck(:action_id)
  end

  test "a step whose change needs a person says why under how the fix stands, so the thread never reads it as clean" do
    @plan.apply!(by: @alice, from: AbilityGateway::SOURCE_SLACK)
    code = @plan.steps.third
    code.update_columns(status: Investigation::RemediationStep::STATUS_DONE, needs_person: "#{PULL} changes infra/prod.tf, which this workspace keeps out of code changes.")

    blocks = Slack::Messages::FixProgress.build(@plan.reload)

    assert_equal ":warning:  Step 3: #{PULL} changes infra/prod.tf, which this workspace keeps out of code changes.", blocks.fourth.dig(:text, :text)
  end

  private

  def state_line(plan) = Slack::Messages::FixProgress.build(plan).third.dig(:text, :text)

  def card_with(blocks, action_id)
    blocks.find { |block| block[:type] == "card" && Array(block[:actions]).any? { |button| button[:action_id] == action_id } }
  end

  def buttons(plan)
    Slack::Messages::FixProgress.build(plan).flat_map { |block| block[:type] == "actions" ? block[:elements] : Array(block[:actions]) }
  end

  def undo_button(plan) = buttons(plan).find { |element| element[:action_id] == Identifiers::UNDO_FIX }
end
