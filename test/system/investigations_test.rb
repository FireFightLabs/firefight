require "application_system_test_case"

class InvestigationsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    FeatureFlags.enable!(@workspace, FeatureFlags::AI_SRE)
    Entitlements.stubs(:allows?).returns(true)
    sign_in(users(:alice), @workspace)
    @incident = incidents(:active_critical_ws1)
    @investigation = @workspace.investigations.create!(
      subject: @incident, trigger_source: Investigation::TRIGGER_COMMAND, triggered_by: workspace_memberships(:alice_workspace_one),
      max_turns: 10, max_spend_cents: 400, status: Investigation::STATUS_SUCCEEDED,
      created_at: 140.seconds.ago, started_at: 133.seconds.ago, completed_at: Time.current, turns_used: 13,
      brief: { Investigation::Brief::KEY_SYMPTOM => "The billing page shows Something went wrong for every admin" }
    )
    @investigation.note_started!
    @investigation.record_hypothesis!(assertion: "A deploy changed the billing plan lookup").update!(created_at: 125.seconds.ago)
    changes = step(1, "Changes before 14:02 in acme/cloud", "3 commits, none touching billing", 120)
    @investigation.record_hypothesis!(assertion: "The billing page calls a method nothing defines").update!(created_at: 105.seconds.ago)
    read = step(2, "Read app/controllers/billing_controller.rb", "before_action :require_admin!", 100)
    step(3, "Find where require_admin! is defined", "require_admin! is not defined in acme/cloud, acme/app.", 80)
    @investigation.record_hypothesis!(assertion: "A deploy changed the billing plan lookup", status: Investigation::Hypothesis::STATUS_REFUTED, steps: [ changes.position ])
    @investigation.record_hypothesis!(assertion: "The billing page calls a method nothing defines", status: Investigation::Hypothesis::STATUS_SUPPORTED, confidence: 0.9, steps: [ 2, 3 ])
    finding = @investigation.conclude!(
      summary: "The billing controller runs before_action :require_admin!, which is defined nowhere, so every signed in visit fails.",
      hypothesis_assertion: "The billing page calls a method nothing defines",
      evidence: [ { claim: "The controller calls require_admin! before every action", steps: [ read.position ] },
                  { claim: "Nothing in either repository defines it", steps: [ 3 ] } ],
      gaps: "Production logs, since none are connected",
      fix: { "summary" => "Define require_admin! where the other guards live",
             "steps" => [ { "kind" => "pull_request", "description" => "Add require_admin! to ApplicationController", "repository" => "acme/cloud" } ] }
    )
    @investigation.note_answered!(finding)
  end

  test "a run opens from the incident's timeline and tells what it was asked, what it found and how" do
    visit incident_path(@incident)
    assert_text "found"
    click_link "an answer"

    within("[role=dialog]") do
      assert_text "The billing page shows Something went wrong for every admin"
      assert_selector "h3", text: /why it thinks so/i
      assert_text "Ruled out"
      assert_text "Find where require_admin! is defined"
      click_button "Show what it returned", match: :first
      assert_text "3 commits, none touching billing"
    end
    assert_current_path incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-sheet.png"))

    find("[role=dialog] button", text: /close/i, visible: :all).click
    assert_no_selector "[role=dialog]"
    assert_current_path incident_path(@incident)
    page.save_screenshot(Rails.root.join("tmp/screenshots/incident-timeline-investigation.png"))
  end

  test "the story says where the run shortened its working notes, between the steps it came between" do
    @investigation.chat_record.compactions.create!(stage: Chat::Compaction::STAGE_CLEARED, tokens_before: 90_000, tokens_freed: 20_000,
                                                   note: "The pool config looks guilty", created_at: 90.seconds.ago)

    visit incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)

    within("[role=dialog]") do
      line = find("li", text: Chat::Compaction::SHOWN_AS)
      assert_text(/Read app\/controllers\/billing_controller\.rb.*#{Chat::Compaction::SHOWN_AS}.*Find where require_admin! is defined/m)
      assert_no_text "The pool config looks guilty"
      execute_script("arguments[0].scrollIntoView({ block: 'center' })", line)
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-made-room.png"))
  end

  test "the run's own link, the one Slack carries, opens it over its incident" do
    visit investigation_path(@investigation)

    within("[role=dialog]") { assert_text "The billing controller runs before_action :require_admin!" }
    assert_text @incident.name
  end

  test "a responder steers a running run from its panel, and the story shows where the run read the note" do
    @investigation.update_columns(status: Investigation::STATUS_RUNNING, completed_at: nil)
    @investigation.finding.destroy!
    bob = workspace_memberships(:bob_workspace_one)
    @investigation.add_note!("It started right after the 14:02 deploy", by: bob)
    @investigation.notes.sole.update!(created_at: 110.seconds.ago, taken_at: 102.seconds.ago)

    visit incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)

    within("[role=dialog]") do
      assert_text bob.display_name
      assert_text "It started right after the 14:02 deploy"
      fill_in "Tell Halon something", with: "Skip GitHub and look at 5xx errors on web"
      click_button "Add to the run"
      assert_text "added, waiting for the next step"
      assert_text "Skip GitHub and look at 5xx errors on web"
    end
    assert_equal 2, @investigation.notes.count
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-notes.png"))
  end

  test "files shared with the ask are named in the story after the run read them, and one it did not read says so" do
    member = workspace_memberships(:alice_workspace_one)
    log = Chat::Attachment.take!(workspace: @workspace, uploaded_by: member, filename: "checkout.log", bytes: "pool exhausted at 14:03")
    dump = Chat::Attachment.unread!(workspace: @workspace, uploaded_by: member, filename: "core.dump", byte_size: 9,
                                    refusal: "core.dump is not a file Halon reads.")
    @investigation.hand_over_files!([ log, dump ], by: member)
    @investigation.take_notes!
    @investigation.notes.sole.update!(created_at: 130.seconds.ago, taken_at: 128.seconds.ago)

    visit incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)

    within("[role=dialog]") do
      assert_text Investigation::Noting::FILES_WITH_THE_ASK
      within("ul[aria-label='Files added']") do
        assert_text "checkout.log"
        assert_selector "[title='core.dump is not a file Halon reads.']", text: "Not read"
      end
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-note-files.png"))
  end

  private

  def step(position, label, result, seconds_ago)
    step = @investigation.steps.create!(
      position: position, tool_name: "github_tool", label: label, action_key: "github.tool",
      status: Investigation::Step::STATUS_RUNNING, started_at: seconds_ago.seconds.ago
    )
    step.succeed!(compacted_result: result)
    step.update!(completed_at: (seconds_ago - 3).seconds.ago)
    step
  end
end
