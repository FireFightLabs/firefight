require "test_helper"

class IncidentLinkWorkflowTest < ActiveSupport::TestCase
  fixtures :workspaces, :users, :workspace_memberships, :incident_lifecycle_stages,
           :incident_statuses, :incident_severities, :incidents

  setup do
    @workspace = workspaces(:slack_workspace_one)
    @member = workspace_memberships(:alice_workspace_one)
    @source = incidents(:active_critical_ws1)
    @target = incidents(:active_major_ws1)
  end

  test "related workflow posts messages to both channels" do
    stub_post_message
    stub_update_message
    stub_set_channel_topic

    IncidentLinkWorkflow.start_inline!(@source, context: {
      linked_by_platform_user_id: @member.platform_user_id,
      target_incident_id: @target.id,
      relationship_type: IncidentRelationship::RELATED
    })

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.link.v1", subject: @source)
    assert_equal "succeeded", workflow.state
  end

  test "duplicate workflow posts messages to both channels" do
    stub_post_message
    stub_update_message
    stub_set_channel_topic

    IncidentLinkWorkflow.start_inline!(@source, context: {
      linked_by_platform_user_id: @member.platform_user_id,
      target_incident_id: @target.id,
      relationship_type: IncidentRelationship::DUPLICATE
    })

    workflow = SolidWorkflow::Workflow.find_by!(name: "incident.link.v1", subject: @source)
    assert_equal "succeeded", workflow.state
  end

  test "duplicate workflow refreshes the source channel topic" do
    stub_post_message
    stub_update_message
    canceled_status = @workspace.incident_statuses.canceled.active.ordered.first
    @source.update!(incident_status: canceled_status)

    Slack::Client.expects(:set_channel_topic).with do |**args|
      args[:channel] == @source.channel_id && args[:topic].include?(canceled_status.name)
    end.returns({ ok: true })

    IncidentLinkWorkflow.start_inline!(@source, context: {
      linked_by_platform_user_id: @member.platform_user_id,
      target_incident_id: @target.id,
      relationship_type: IncidentRelationship::DUPLICATE
    })
  end

  test "related workflow leaves the source channel topic alone" do
    stub_post_message
    stub_update_message

    Slack::Client.expects(:set_channel_topic).never

    IncidentLinkWorkflow.start_inline!(@source, context: {
      linked_by_platform_user_id: @member.platform_user_id,
      target_incident_id: @target.id,
      relationship_type: IncidentRelationship::RELATED
    })
  end
end
