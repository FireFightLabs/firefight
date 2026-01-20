class SlackWorkspaceSetupWorkflow < Base
  workflow_name "slack.workspace_setup.v1"

  step :create_incidents_channel
  step :set_channel_metadata, depends_on: [ :create_incidents_channel ]
  step :post_welcome_message, depends_on: [ :set_channel_metadata ]
  step :invite_installer, depends_on: [ :post_welcome_message ]
  step :store_channel_id, depends_on: [ :create_incidents_channel ]


  def create_incidents_channel(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)

    result = adapter.create_incidents_channel

    Rails.logger.info({
      event: "workspace_setup.channel_created",
      message: "Created main public incidents channel",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      platform: workspace.platform,
      channel_id: result[:channel_id],
      channel_name: result[:channel_name],
      already_existed: result[:already_existed]
    })

    result
  end


  def set_channel_metadata(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)

    channel_id = input["create_incidents_channel"]["channel_id"]
    adapter.set_channel_metadata(channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.metadata_set",
      message: "Set channel topic and description",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id
    })

    { success: true }
  end


  def invite_installer(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)

    channel_id = input["create_incidents_channel"]["channel_id"]
    installer_user_id = workflow.context["installer_user_id"]


    if input["create_incidents_channel"]["already_existed"]
      Rails.logger.info({
        event: "workspace_setup.invite_skipped",
        message: "Skipping user invite, channel already existed",
        workflow_id: workflow.id,
        workspace_id: workspace.id,
        channel_id: channel_id
      })

      return { skipped: true }
    end

    adapter.invite_user(
      channel_id: channel_id,
      user_id: installer_user_id
    )

    Rails.logger.info({
      event: "workspace_setup.user_invited",
      message: "Invited installer to incidents channel",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id,
      user_id: installer_user_id
    })

    { invited_user: installer_user_id }
  end


  def post_welcome_message(workflow:, step:, input:)
    workspace = workflow.subject
    adapter = WorkspaceAdapter.for(workspace)

    channel_id = input["create_incidents_channel"]["channel_id"]
    result = adapter.post_welcome_message(channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.welcome_posted",
      message: "Posted welcome message to incidents channel",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id,
      message_ts: result[:message_ts]
    })

    result
  end

  def store_channel_id(workflow:, step:, input:)
    workspace = workflow.subject
    channel_id = input["create_incidents_channel"]["channel_id"]

    workspace.update!(incidents_channel_id: channel_id)

    Rails.logger.info({
      event: "workspace_setup.channel_stored",
      message: "Stored incidents channel ID in workspace",
      workflow_id: workflow.id,
      workspace_id: workspace.id,
      channel_id: channel_id
    })

    { workspace_id: workspace.id, channel_id: channel_id }
  end
end
