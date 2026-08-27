module Slack::WorkspaceAdapter::IncidentModals
  extend ActiveSupport::Concern

  MODAL_BUILDERS = {
    PlatformAdapter::Modal::INCIDENT_CREATION => ->(workspace, **options) { Slack::Modals::IncidentCreation.build(workspace: workspace, **options) },
    PlatformAdapter::Modal::INCIDENT_CREATED => ->(workspace, incident) { Slack::Modals::IncidentCreated.build(incident, team_id: workspace.platform_id) },
    PlatformAdapter::Modal::INCIDENT_UPDATE => ->(_, incident, **options) { Slack::Modals::IncidentUpdate.build(incident, **options) },
    PlatformAdapter::Modal::INCIDENT_CLOSE => ->(_, incident, **options) { Slack::Modals::IncidentClose.build(incident, **options) },
    PlatformAdapter::Modal::INCIDENT_CANCEL => ->(_, incident, **options) { Slack::Modals::IncidentCancel.build(incident, **options) },
    PlatformAdapter::Modal::REOPEN => ->(_, incident, **options) { Slack::Modals::Reopen.build(incident, **options) },
    PlatformAdapter::Modal::SUMMARY => ->(_, incident, **options) { Slack::Modals::Summary.build(incident, **options) },
    PlatformAdapter::Modal::ESCALATE => ->(_, incident, **options) { Slack::Modals::Escalate.build(incident, **options) },
    PlatformAdapter::Modal::INVITE => ->(_, incident, **options) { Slack::Modals::Invite.build(incident, **options) },
    PlatformAdapter::Modal::LEAD => ->(_, incident) { Slack::Modals::Lead.build(incident) },
    PlatformAdapter::Modal::ROLES => ->(_, incident, roles) { Slack::Modals::Roles.build(incident, roles) },
    PlatformAdapter::Modal::ATTACH_RUNBOOK => ->(_, incident, runbooks) { Slack::Modals::AttachRunbook.build(incident, runbooks) },
    PlatformAdapter::Modal::RUNBOOK_DETAIL => ->(_, incident_runbook) { Slack::Modals::RunbookDetail.build(incident_runbook) },
    PlatformAdapter::Modal::ACTION_ITEMS_LIST => ->(_, incident, kind:) { Slack::Modals::ActionItemsList.build(incident, kind: kind) },
    PlatformAdapter::Modal::ACTION_ITEMS_FORM => ->(_, incident, **options) { Slack::Modals::ActionItemsForm.build(incident, **options) },
    PlatformAdapter::Modal::SHOUTOUT => ->(_, incident) { Slack::Modals::Shoutout.build(incident) },
    PlatformAdapter::Modal::HOME => ->(_, channel_id:) { Slack::Modals::Home.build(channel_id: channel_id) }
  }.freeze

  def build_modal(kind, *args, metadata: nil, **options)
    options[:private_metadata] = metadata if metadata
    MODAL_BUILDERS.fetch(kind).call(@workspace, *args, **options)
  end

  def parse_form_submission(form_slug:, values:, incident: nil)
    Slack::FormSubmission.new(workspace: @workspace, form_slug: form_slug, values: values, incident: incident).parse
  end

  def form_error_response(field_key, message)
    { response_action: "errors", errors: { Slack::Modals::FieldBlocks.block_id(field_key) => message } }
  end

  def form_update_response(view)
    { response_action: "update", view: view }
  end

  def update_modal(view_id:, view:)
    translate_errors do
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  # Refreshes the open incident-creation modal with new dispatch context
  # (severity / type selected via dispatch_action) without losing other
  # user-entered values.
  def update_incident_creation_modal(view_id:, state: {})
    translate_errors do
      view = Slack::Modals::IncidentCreation.build(workspace: @workspace, state: state)
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  # Refreshes the open update modal after its status select dispatches, so the
  # fields on it match the status the responder has just picked.
  def update_incident_update_modal(view_id:, incident:, state: {}, private_metadata: nil)
    translate_errors do
      view = Slack::Modals::IncidentUpdate.build(incident, private_metadata: private_metadata, state: state)
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  # Patches the home modal's help section based on the selected command,
  # preserving everything else about the open view.
  def update_home_modal(view:, selected_command:)
    translate_errors do
      help_text = Slack::Modals::Home.command_help(selected_command)
      updated_blocks = view["blocks"].map do |block|
        if block["block_id"] == "command_details_block"
          block.merge("text" => { "type" => "mrkdwn", "text" => help_text })
        else
          block
        end
      end

      Slack::Client.update_modal(
        workspace: @workspace,
        view_id: view["id"],
        view: {
          type: "modal",
          callback_id: Identifiers::INCIDENT_HOME_MODAL,
          private_metadata: view["private_metadata"],
          title: view["title"],
          submit: view["submit"],
          close: view["close"],
          blocks: updated_blocks
        }
      )

      { success: true }
    end
  end

  # Push-vs-open dispatch: open as a top-level modal when invoked directly,
  # or push onto an existing stack when invoked from another modal (e.g.
  # the actions list).
  def open_action_item_modal(kind:, trigger_id:, incident:, private_metadata: nil, push: false)
    view = Slack::Modals::ActionItemsForm.build(incident, kind: kind, private_metadata: private_metadata)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  # Skip opening the link modal when there's nothing in the workspace to
  # link to. The build returns nil in that case.
  def open_link_incident_modal(trigger_id:, incident:, private_metadata: nil, default_type: IncidentRelationship::RELATED)
    view = Slack::Modals::Link.build(incident, private_metadata: private_metadata, default_type: default_type)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end
end
