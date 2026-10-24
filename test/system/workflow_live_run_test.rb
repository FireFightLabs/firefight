require "application_system_test_case"

class WorkflowLiveRunTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  SHOTS = ENV["WORKFLOW_LIVE_RUN_SHOTS"]

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @alice = workspace_memberships(:alice_workspace_one)
    FirefightAi::WorkflowRepair.any_instance.stubs(:suggest).returns(nil)
    WorkspaceAdapter.for(@workspace).class.any_instance.stubs(:post_workflow_failure).returns({})
    Workflow::Version.any_instance.stubs(:step_problems).returns([])
    @workflow = Workflow.create!(workspace: @workspace, name: "Production release", created_by: @alice)
    draft = @workflow.open_draft!(by: @alice)
    draft.update!(
      trigger: { "kind" => "manual", "inputs" => [] },
      steps: [
        { "id" => "look", "name" => "report_open_incidents", "kind" => "call_tool", "config" => { "tool" => FirefightTools::SEARCH_INCIDENTS, "arguments" => { "query" => "checkout" } } },
        { "id" => "follow", "name" => "watch_the_rollout", "kind" => "watch",
          "config" => { "title" => "Rollout", "steps" => [ { "label" => "Web rollout", "capability" => "status", "resource" => "web", "done_when" => "running" } ] } }
      ],
      edges: [ { "from" => "look", "to" => "follow" } ]
    )
    result = WorkflowPublishService.new(@workflow).publish!(draft.reload, by: @alice)
    assert result.ok, result.words
    Conversation::Watches.stubs(:start).with do |host, _given|
      watch = Chat::Watch.create!(chat: host.chat, workspace: host.workspace, asker: host.asker, title: "Rollout", expires_at: 50.minutes.from_now,
                                  limit_basis: Chat::Watch::BASIS_DEFAULT, checked_at: 20.seconds.ago, reads_total: 4)
      Chat::Watch::Step.create!(watch: watch, position: 1, label: "Web rollout", capability: Integrations::Capabilities::STATUS, status: Chat::Watch::Step::STATUS_WAITING,
                                summary: "Waiting for a924eed to deploy to web (live now: 86a37b0 since 09:13 UTC).", new_deploy: { "commit" => "a924eed" }, run_url: "https://example.com/runs/97")
      Chat::Watch::Update.create!(watch: watch, kind: Chat::Watch::Update::KIND_STARTED, text: "Watching Web rollout.")
      true
    end.returns("Started")
  end

  def start!
    run = nil
    perform_enqueued_jobs { run = WorkflowRunService.new(@workflow.reload).start!(started_by_kind: Workflow::Run::STARTED_BY_PERSON, started_by: @alice) }
    run.reload
  end

  def shot(name)
    page.save_screenshot(File.join(SHOTS, "#{name}.png")) if SHOTS
  end

  test "a live run says what each step is doing now, and keeps each step's log once it ends" do
    run = start!
    assert_equal Workflow::Run::STATUS_WAITING, run.status
    record = run.steps.find_by!(step_key: "follow")
    3.times do |index|
      Ability::Invocation.create!(workspace: @workspace, principal: @workflow.agent, principal_label: "Production release workflow", action_key: "integrations.northflank.list_deployments",
                                  decision: Ability::Invocation::DECISION_ALLOW, outcome: Ability::Invocation::OUTCOME_SUCCESS, duration_ms: 240, source: Chat::Watch::SOURCE,
                                  idempotency_key: SecureRandom.uuid, created_at: (3 - index).minutes.ago, completed_at: (3 - index).minutes.ago, **record.ledger_context)
    end

    sign_in(users(:alice), @workspace)
    visit workflow_path(@workflow, run: run.id)

    within("aside[aria-label='Run']") do
      within("section[aria-label='Now']") do
        assert_text "Watch the rollout: Web rollout: Waiting for a924eed to deploy to web"
        assert_text "It reads next"
      end
      within("section[aria-label='Steps']") do
        assert_text "Report open incidents"
        assert_text "Done."
      end
    end
    shot("live-run")

    within("section[aria-label='Steps']") { click_button "Watch the rollout" }
    within("aside[aria-label='Run']") do
      within("section[aria-label='The watch']") do
        assert_text "Waiting for a924eed to deploy to web"
        assert_link "Open the run", href: "https://example.com/runs/97"
        assert_text "Gives up at"
      end
      within("section[aria-label='What it did']") do
        assert_text "Watching Web rollout."
        assert_text "Read integrations.northflank.list_deployments (3 times)"
      end
    end
    shot("live-run-watch-step")

    perform_enqueued_jobs { Conversation::Watches.finish!(Chat::Watch.sole, Chat::Watch::STATUS_TIMED_OUT, "Last I saw: Web rollout: waiting for a924eed.") }

    # The page reads the run again on its own while it goes, so the end shows without a reload.
    within("aside[aria-label='Run']") do
      assert_text "Failed. It took the timed out way.", wait: 15
      assert_text "Watch the rollout timed out after 50 minutes."
      assert_no_text "Gives up at"
    end
    shot("finished-run-watch-step")

    click_button "The whole run"
    within("aside[aria-label='Run']") do
      assert_text "Failed"
      assert_no_selector "section[aria-label='Now']"
      within("section[aria-label='Steps']") { assert_text "Watch the rollout" }
    end
    shot("finished-run")

    find("section[aria-label='Steps'] button", text: "Report open incidents").click
    within("section[aria-label='What it did']") { assert_text "search_incidents answered." }
    shot("finished-run-tool-step")
  end
end
