class SlackWorkspaceSetupWorkflow < SolidWorkflow::Base
  workflow_name "slack.workspace_setup.v1"

  step :create_incidents_channel
  step :set_channel_metadata, depends_on: [ :create_incidents_channel ]
  step :post_welcome_message, depends_on: [ :set_channel_metadata ]
  step :invite_installer, depends_on: [ :post_welcome_message ]
  step :store_channel_id, depends_on: [ :create_incidents_channel ]

  def create_incidents_channel(workflow:, step:, input:)
    setup_service(workflow).create_incidents_channel(workflow.subject)
  end

  def set_channel_metadata(workflow:, step:, input:)
    channel_id = input["create_incidents_channel"]["channel_id"]
    setup_service(workflow).set_channel_metadata(workflow.subject, channel_id)
  end

  def invite_installer(workflow:, step:, input:)
    channel_id = input["create_incidents_channel"]["channel_id"]
    installer_user_id = workflow.context["installer_user_id"]
    skip_if_existed = input["create_incidents_channel"]["already_existed"]

    setup_service(workflow).invite_user(
      workflow.subject,
      channel_id,
      installer_user_id,
      skip_if_channel_existed: skip_if_existed
    )
  end

  def post_welcome_message(workflow:, step:, input:)
    channel_id = input["create_incidents_channel"]["channel_id"]
    setup_service(workflow).post_welcome_message(workflow.subject, channel_id)
  end

  def store_channel_id(workflow:, step:, input:)
    channel_id = input["create_incidents_channel"]["channel_id"]
    setup_service(workflow).store_channel_id(workflow.subject, channel_id)
  end

  private

  def setup_service(workflow)
    @setup_service ||= WorkspaceSetupService.new(workflow.subject)
  end
end
