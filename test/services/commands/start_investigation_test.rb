require "test_helper"

class Commands::StartInvestigationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @member = workspace_memberships(:alice_workspace_one)
    stub_post_message
  end

  test "a responder in an incident channel starts a run" do
    assert_enqueued_with(job: InvestigationJob) do
      assert_nil Commands::StartInvestigation.execute(build_command)
    end

    investigation = @incident.investigations.sole
    assert_equal Investigation::TRIGGER_COMMAND, investigation.trigger_source
    assert_equal @member, investigation.triggered_by
  end

  test "the words after the command are what the person already knows, kept for the run" do
    Commands::StartInvestigation.execute(build_command(text: "#{Identifiers::SUBCOMMAND_INVESTIGATE} checkout 500s since 2pm"))

    brief = @incident.investigations.sole.brief
    assert_equal "checkout 500s since 2pm", brief[Investigation::Brief::KEY_SYMPTOM]
    assert_equal Investigation::Brief::SOURCE_COMMAND, brief[Investigation::Brief::KEY_SOURCE]
  end

  test "the run reads the words with each person named and their id kept, and the page keeps them as written" do
    bob = workspace_memberships(:bob_workspace_one)
    written = "<@#{bob.platform_user_id}> says checkout is :fire:"

    Commands::StartInvestigation.execute(build_command(text: "#{Identifiers::SUBCOMMAND_INVESTIGATE} #{written}"))

    run = @incident.investigations.sole
    read = "@#{bob.display_name} (#{bob.platform_user_id}) says checkout is 🔥"
    assert_equal written, run.question
    assert_equal read, run.question_for_model
    assert_equal({ Investigation::Brief::KEY_SYMPTOM => read, Investigation::Brief::KEY_SOURCE => Investigation::Brief::SOURCE_COMMAND }, run.brief_for_model)
    assert_equal read, Investigation::QuestionSeed.new(run).gather["question"]
  end

  test "a code change written for a run's fix is told what was asked and noted as the run read it" do
    bob = workspace_memberships(:bob_workspace_one)
    Commands::StartInvestigation.execute(build_command(text: "#{Identifiers::SUBCOMMAND_INVESTIGATE} ask <@#{bob.platform_user_id}>"))
    run = @incident.investigations.sole
    run.update!(status: Investigation::STATUS_RUNNING)
    run.add_note_from("and @#{bob.display_name} (#{bob.platform_user_id})", member: @member, source: AbilityGateway::SOURCE_SLACK,
                                                                              as_written: "and <@#{bob.platform_user_id}>")
    finding = run.create_finding!(summary: "A bad deploy")
    plan = finding.create_remediation_plan!(summary: "Roll back")
    step = plan.steps.create!(position: 1, kind: Investigation::RemediationStep::KIND_PULL_REQUEST, description: "Revert it", repository: "acme/web")

    words = step.code_agent_request(@member).words

    assert_equal [ "ask @#{bob.display_name} (#{bob.platform_user_id})", "and @#{bob.display_name} (#{bob.platform_user_id})" ], words
  end

  test "a blocked entitlement stops the run with its own sentence" do
    message = deny_entitlements!

    result = Commands::StartInvestigation.execute(build_command)

    assert_equal message, result[:text]
    assert_empty @incident.investigations
  end

  test "outside an incident channel it investigates what the person said, and answers in that channel" do
    assert_enqueued_with(job: InvestigationJob) do
      assert_nil Commands::StartInvestigation.execute(build_command(channel_id: "C00000000", text: "#{Identifiers::SUBCOMMAND_INVESTIGATE} checkout is slow"))
    end

    investigation = @workspace.investigations.find_by!(channel_id: "C00000000")
    assert_nil investigation.subject
    assert_equal "checkout is slow", investigation.question
  end

  test "with AI blocked, outside an incident channel it says why before asking anything" do
    message = deny_entitlements!

    result = Commands::StartInvestigation.execute(build_command(channel_id: "C00000000"))

    assert_equal message, result[:text]
  end

  test "outside an incident channel, with nothing said, it asks what is wrong" do
    result = nil
    assert_no_enqueued_jobs(only: InvestigationJob) { result = Commands::StartInvestigation.execute(build_command(channel_id: "C00000000")) }

    assert_equal Investigation::NEEDS_A_QUESTION, result[:text]
  end

  # A command only resolves a live incident, so a finished channel reads as no incident at all.
  test "in a channel whose incident is over it investigates the question, not the finished incident" do
    resolved = incidents(:resolved_minor_ws1)

    Commands::StartInvestigation.execute(build_command(channel_id: resolved.channel_id, text: "#{Identifiers::SUBCOMMAND_INVESTIGATE} is it back"))

    assert_empty resolved.investigations
    assert_equal "is it back", @workspace.investigations.find_by!(channel_id: resolved.channel_id).question
  end

  test "a second ask is told about the run already going" do
    Commands::StartInvestigation.execute(build_command)

    result = nil
    assert_no_enqueued_jobs(only: InvestigationJob) { result = Commands::StartInvestigation.execute(build_command) }

    assert_match "Already investigating", result[:text]
    assert_equal 1, @incident.investigations.count
  end

  test "declares investigations.create as its authorization" do
    assert_equal [ Ability::Action::RESOURCE_INVESTIGATIONS, Ability::Action::ACTION_CREATE ],
                 Commands::StartInvestigation.authorization
  end

  private

  def build_command(channel_id: nil, text: Identifiers::SUBCOMMAND_INVESTIGATE)
    Command.new(
      platform: Platforms::SLACK, workspace_id: @workspace.id, user_id: @member.platform_user_id,
      text: text, trigger_id: "12345.trigger",
      channel_id: channel_id || @incident.channel_id, metadata: { command: "/ff" }
    )
  end
end
