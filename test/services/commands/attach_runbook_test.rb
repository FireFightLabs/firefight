require "test_helper"

class Commands::AttachRunbookTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_severities,
           :incident_lifecycle_stages, :incident_statuses, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @incident = incidents(:active_critical_ws1)
    @runbook = @workspace.runbooks.create!(name: "Database outage")
    @runbook.runbook_steps.create!(title: "Check the pool", position: 1)
  end

  test "the command opens the picker" do
    stub_open_modal

    assert_nil Commands::AttachRunbook.execute(command)
  end

  test "the picker offers only runbooks that are not attached yet" do
    attached = @workspace.runbooks.create!(name: "Already on this incident")
    @incident.incident_runbooks.create!(runbook: attached, workspace: @workspace)

    view = Slack::Modals::AttachRunbook.build(@incident, @incident.attachable_runbooks)

    assert_equal Identifiers::ATTACH_RUNBOOK_MODAL, view[:callback_id]
    values = view[:blocks].first[:element][:options].map { |option| option[:value] }
    assert_equal [ @runbook.slug ], values
  end

  test "the command says so rather than opening an empty picker" do
    @incident.incident_runbooks.create!(runbook: @runbook, workspace: @workspace)

    result = Commands::AttachRunbook.execute(command)

    assert_match "already attached", result[:text]
  end

  test "the command refuses outside an incident channel" do
    result = Commands::AttachRunbook.execute(command(channel_id: "C_NOT_AN_INCIDENT"))

    assert_match "active incident channel", result[:text]
  end

  private

  def command(channel_id: @incident.channel_id)
    Command.new(
      platform: Platforms::SLACK,
      workspace_id: @workspace.id,
      user_id: @member.platform_user_id,
      channel_id: channel_id,
      text: Identifiers::SUBCOMMAND_RUNBOOK,
      trigger_id: "12345.trigger"
    )
  end
end
