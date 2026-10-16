require "test_helper"

# Run it in Slack: on the runbook's message in the incident channel and in its detail view, only where the runbook links
# a workflow. It asks the run's questions and starts the workflow as the workflow's own identity.
class Interactions::RunbookRunHandlersTest < ActiveSupport::TestCase
  setup do
    @workspace = workspaces(:slack_workspace_one)
    @admin = workspace_memberships(:alice_workspace_one)
    @member = workspace_memberships(:bob_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @runbook = @workspace.runbooks.create!(name: "Release Firefight", inputs: [ { key: "bump", question: "Which version bump?", default: "patch" },
                                                                                { key: "note", question: "Anything to say?" } ])
    @runbook.sync_steps!([ { title: "Look for past releases", tool: "search_incidents", arguments: { "query" => "{{bump}}" } }, { title: "Tell the team" } ])
    @runbook.reload.move_runnable_parts!
    @incident_runbook = @incident.incident_runbooks.create!(runbook: @runbook, workspace: @workspace)
  end

  test "a runbook that links a workflow offers Run it on its message and in its detail view" do
    workflow = publish_workflow

    assert_includes action_ids(Slack::Messages::Runbook.attached(@incident_runbook.reload)), Identifiers::RUN_RUNBOOK
    detail = Slack::Modals::RunbookDetail.build(@incident_runbook)[:blocks]
    assert_equal Identifiers::RUN_RUNBOOK, detail.second[:elements].sole[:action_id]
    assert workflow.live?
    guide = @workspace.runbooks.create!(name: "Database failover")
    assert_not_includes action_ids(Slack::Messages::Runbook.attached(@incident.incident_runbooks.create!(runbook: guide, workspace: @workspace))), Identifiers::RUN_RUNBOOK
  end

  test "Run it opens the form with each question, its default filled in, and pushes it over the detail view" do
    publish_workflow
    stub_open_modal
    stub_push_modal
    opened = nil
    Slack::Client.expects(:open_modal).with { |**args| opened = args[:view] }.returns({ ok: true, view: { id: "V1" } })

    Interactions::RunRunbookHandler.execute(press)

    assert_equal Identifiers::RUNBOOK_RUN_MODAL, opened[:callback_id]
    inputs = opened[:blocks].select { |block| block[:type] == "input" }
    assert_equal [ "Which version bump?", "Anything to say?" ], inputs.map { |block| block.dig(:label, :text) }
    assert_equal "patch", inputs.first.dig(:element, :initial_value)
    assert_nil inputs.second.dig(:element, :initial_value)

    Slack::Client.expects(:push_modal).returns({ ok: true, view: { id: "V2" } })
    Interactions::RunRunbookHandler.execute(press(view_id: "V1"))
  end

  test "Run it on a draft says privately why it cannot run, and opens nothing" do
    Slack::Client.expects(:open_modal).never
    Slack::Client.expects(:post_ephemeral).with { |**args| args[:text] == "Release Firefight has no published version to run." }.returns({ ok: true })

    Interactions::RunRunbookHandler.execute(press)
  end

  test "submitting the form starts the workflow for the incident and tells the person where to follow it" do
    workflow = publish_workflow
    told = nil
    Slack::Client.expects(:post_ephemeral).with { |**args| told = args }.returns({ ok: true })

    answer = Interactions::RunbookRunHandler.execute(submit("bump" => "minor", "note" => "Ship it"))

    assert_nil answer
    run = workflow.runs.sole
    assert_equal [ workflow.agent, Workflow::Run::STARTED_BY_PERSON, @member ], [ run.agent, run.started_by_kind, run.started_by ]
    assert_equal({ "bump" => "minor", "note" => "Ship it" }, run.inputs)
    assert_equal @incident.identifier, run.trigger_payload.dig("incident", "identifier")
    assert_equal [ @incident.channel_id, @member.platform_user_id ], told.values_at(:channel, :user)
    assert_equal "Release Firefight is running. <#{Workflow::Links.run(run)}|Follow its run>", told[:text]
  end

  test "a form missing an answer with no default turns into why the run did not start" do
    workflow = publish_workflow

    answer = Interactions::RunbookRunHandler.execute(submit("bump" => "", "note" => ""))

    assert_equal "update", answer[:response_action]
    assert_match "Release Firefight needs a value for note.", answer.dig(:view, :blocks).sole.dig(:text, :text)
    assert_empty workflow.runs
  end

  private

  def publish_workflow
    workflow = @runbook.reload.workflow
    result = WorkflowPublishService.new(workflow).publish!(workflow.draft, by: @admin)
    assert result.ok, result.words
    workflow.reload
  end

  def action_ids(blocks)
    blocks.select { |block| block[:type] == "actions" }.flat_map { |block| block[:elements].map { |element| element[:action_id] } }
  end

  def press(view_id: nil)
    Interaction.new(platform: Platforms::SLACK, type: Interaction::BLOCK_ACTIONS, team_id: @workspace.platform_id, user_id: @member.platform_user_id,
                    trigger_id: "T1", channel_id: @incident.channel_id, action_id: Identifiers::RUN_RUNBOOK, action_value: @incident_runbook.id, view_id: view_id)
  end

  def submit(answers)
    values = answers.to_h { |key, value| [ "#{Slack::Modals::RunbookRun::INPUT_BLOCK_PREFIX}#{key}", { Slack::Modals::RunbookRun::INPUT_ACTION => { "value" => value } } ] }
    Interaction.new(platform: Platforms::SLACK, type: Interaction::VIEW_SUBMISSION, team_id: @workspace.platform_id, user_id: @member.platform_user_id,
                    callback_id: Identifiers::RUNBOOK_RUN_MODAL, values: values,
                    private_metadata: ModalState.encode(incident_id: @incident.id, incident_runbook_id: @incident_runbook.id))
  end
end
