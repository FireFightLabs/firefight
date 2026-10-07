require "application_system_test_case"

class InvestigationsTest < ApplicationSystemTestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
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

  test "a note's toast shows once while the running run reloads and as its panel closes, and again for a second note" do
    @investigation.update_columns(status: Investigation::STATUS_RUNNING, completed_at: nil)
    @investigation.finding.destroy!

    visit incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)
    # Counts every toast that appears onto the page, since one shown again could replace one still showing.
    page.execute_script(<<~JS, Investigation::Noting::NOTE_ADDED)
      const text = arguments[0]
      document.body.dataset.toastsShown = "0"
      new MutationObserver((mutations) => {
        mutations.flatMap((mutation) => [ ...mutation.addedNodes ]).forEach((node) => {
          if (node.matches?.("[data-sonner-toast]") && node.textContent.includes(text)) {
            document.body.dataset.toastsShown = String(Number(document.body.dataset.toastsShown) + 1)
          }
        })
      }).observe(document.body, { childList: true, subtree: true })
    JS

    within("[role=dialog]") do
      fill_in "Tell Halon something", with: "Skip GitHub"
      click_button "Add to the run"
    end
    assert_toasts_shown 1

    # Two polls land, the second only after anything the first replayed has drawn.
    step(4, "Read the 5xx errors on web", "Mostly 502s", 5)
    within("[role=dialog]") { assert_text "Read the 5xx errors on web", wait: 10 }
    step(5, "Read the load balancer logs", "Nothing unusual", 4)
    within("[role=dialog]") { assert_text "Read the load balancer logs", wait: 10 }
    assert_toasts_shown 1

    within("[role=dialog]") do
      fill_in "Tell Halon something", with: "Look at the database too"
      click_button "Add to the run"
    end
    assert_toasts_shown 2

    find("body").send_keys(:escape)
    assert_no_selector "[role=dialog]"
    assert_current_path incident_path(@incident)
    find("a[href*='#{Investigation::QUERY_PARAM}=#{@investigation.id}']", match: :first).click
    within("[role=dialog]") { assert_text "Look at the database too" }
    assert_toasts_shown 2
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

  test "a note's image opens full size over the story and its log downloads, as a chat's files do" do
    member = workspace_memberships(:alice_workspace_one)
    image = Chat::Attachment.take!(workspace: @workspace, uploaded_by: member, filename: "halon_graph.png", bytes: file_fixture("halon_graph.png").binread)
    log = Chat::Attachment.take!(workspace: @workspace, uploaded_by: member, filename: "checkout.log", bytes: "pool exhausted at 14:03")
    @investigation.hand_over_files!([ image, log ], by: member)
    @investigation.take_notes!
    @investigation.notes.sole.update!(created_at: 130.seconds.ago, taken_at: 128.seconds.ago)

    visit incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)

    within("ul[aria-label='Files added']") do
      download = find("a[aria-label='Download checkout.log']")
      assert_equal incident_investigation_file_path(@incident, @investigation, log), URI(download[:href]).path
      assert_equal "checkout.log", download[:download]
      find("button[aria-label='Open halon_graph.png']").click
    end

    within("[role=dialog]", text: "The image at full size") do
      shown = find("img[alt='halon_graph.png']")
      assert_equal incident_investigation_file_path(@incident, @investigation, image), URI(shown[:src]).path
      assert shown.evaluate_script("this.complete && this.naturalWidth > 0"), "the image loads from the file address under the incident"
      assert_link "Open the original"
    end
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-note-image.png"))
  end

  test "anyone reading the answer rates it partly right, sees their choice and the team's count" do
    visit incident_path(@incident, Investigation::QUERY_PARAM => @investigation.id)

    within("[role=dialog]") do
      within("[aria-label='Rate this answer']") do
        assert_selector "button", text: "Right"
        assert_selector "button", text: "Wrong"
        click_button "Partly right"
      end
    end

    assert_text "Thanks. You rated this answer partly right."
    within("[role=dialog]") do
      assert_selector "[aria-label='Rate this answer'] [data-state=on]", text: "Partly right"
      assert_text "Partly right"
    end
    assert_equal Investigation::Finding::OUTCOME_PARTIAL, @investigation.finding.reload.outcome
    page.save_screenshot(Rails.root.join("tmp/screenshots/investigation-rated-partly-right.png"))
  end

  private

  def assert_toasts_shown(count)
    assert_selector "body[data-toasts-shown='#{count}']"
  end

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
