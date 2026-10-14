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

  def update_incident_creation_modal(view_id:, state: {}, private_metadata: nil, test: false)
    translate_errors do
      view = Slack::Modals::IncidentCreation.build(workspace: @workspace, state: state, private_metadata: private_metadata, test: test)
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

  def update_incident_update_modal(view_id:, incident:, state: {}, private_metadata: nil)
    translate_errors do
      view = Slack::Modals::IncidentUpdate.build(incident, private_metadata: private_metadata, state: state)
      Slack::Client.update_modal(workspace: @workspace, view_id: view_id, view: view)
      { success: true }
    end
  end

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

  # A prompt posted with the words themselves fills the form as it opens. One carrying where the message is opens it
  # empty, to be filled in once the message is read (fill_in_action_item_modal).
  def open_action_item_modal(kind:, trigger_id:, incident:, private_metadata: nil, push: false)
    state = private_metadata.present? ? ModalState.parse(private_metadata) : ModalState::EMPTY
    view = Slack::Modals::ActionItemsForm.build(incident, kind: kind, private_metadata: private_metadata, description: readable(state.source_message_text))
    opened = translate_errors do
      push ? Slack::Client.push_modal(workspace: @workspace, trigger_id: trigger_id, view: view) : Slack::Client.open_modal(workspace: @workspace, trigger_id: trigger_id, view: view)
    end
    { success: true, view_id: opened.dig(:view, :id) }
  end

  # Shown as plain text, since the field takes no markup. A message that cannot be read, or a form closed before it is
  # filled in, leaves the field as it was.
  def fill_in_action_item_modal(view_id:, kind:, incident:, private_metadata:)
    state = ModalState.parse(private_metadata)
    return unless state.source_message_id && state.channel_id

    message = fetch_message(channel_id: state.channel_id, message_id: state.source_message_id)
    # Slack hands back the newest message at or before the one asked for, so a deleted message reads as an older one.
    return unless message[:message_id] == state.source_message_id

    description = readable(message[:text])
    return if description.blank?

    update_modal(view_id: view_id, view: Slack::Modals::ActionItemsForm.build(incident, kind: kind, private_metadata: private_metadata, description: description))
  rescue AdapterError => error
    Rails.logger.info({ event: "slack.action_item_form.fill_in_failed", error: error.class.name, message: error.message }.to_json)
  end

  def open_rename_action_modal(trigger_id:, action:, push: false)
    view = Slack::Modals::RenameAction.build(action)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def renamed_action_title(values:) = Slack::Modals::RenameAction.title(values)

  def rename_action_error(message) = { response_action: "errors", errors: { Slack::Modals::RenameAction::BLOCK => message } }

  def open_runbook_run_modal(trigger_id:, incident_runbook:, push: false)
    view = Slack::Modals::RunbookRun.build(incident_runbook)
    push ? push_modal(trigger_id: trigger_id, view: view) : open_modal(trigger_id: trigger_id, view: view)
  end

  def runbook_run_inputs(values:) = Slack::Modals::RunbookRun.inputs(values)

  def runbook_run_refused(message) = { response_action: "update", view: Slack::Modals::RunbookRun.refused(message) }

  def post_runbook_run_started(channel_id:, user_id:, run:)
    post_ephemeral(channel_id: channel_id, user_id: user_id,
                   text: "#{Slack::Mrkdwn.escape(run.workflow.name)} is running. <#{Workflow::Links.run(run)}|Follow its run>")
  end

  def open_memory_correction_modal(trigger_id:, post_id:, memory:)
    open_modal(trigger_id: trigger_id, view: Slack::Modals::CorrectMemory.build(post_id: post_id, memory: memory))
  end

  def memory_correction(values:) = Slack::Modals::CorrectMemory.values(values)

  def memory_correction_error(message) = { response_action: "errors", errors: { Slack::Modals::CorrectMemory::CORRECTION_BLOCK => message } }

  def open_handbook_proposal_modal(trigger_id:, proposal:)
    open_modal(trigger_id: trigger_id, view: Slack::Modals::EditHandbookProposal.build(proposal))
  end

  def handbook_proposal_text(values:) = Slack::Modals::EditHandbookProposal.text(values)

  def handbook_proposal_error(message) = { response_action: "errors", errors: { Slack::Modals::EditHandbookProposal::TEXT_BLOCK => message } }

  def open_workflow_question_modal(trigger_id:, question:)
    open_modal(trigger_id: trigger_id, view: Slack::Modals::WorkflowQuestionAnswer.build(question))
  end

  def workflow_question_answer(values:) = Slack::Modals::WorkflowQuestionAnswer.answer(values)

  def workflow_question_error(message, question:) = { response_action: "errors", errors: { Slack::Modals::WorkflowQuestionAnswer.error_block(question) => message } }

  def open_code_question_modal(trigger_id:, question:)
    open_modal(trigger_id: trigger_id, view: Slack::Modals::CodeQuestionAnswer.build(question))
  end

  def code_question_answer(values:) = Slack::Modals::CodeQuestionAnswer.answer(values)

  def code_question_error(message) = { response_action: "errors", errors: { Slack::Modals::CodeQuestionAnswer::ANSWER_BLOCK => message } }

  def open_code_question_change_modal(trigger_id:, question:)
    open_modal(trigger_id: trigger_id, view: Slack::Modals::CodeQuestionChange.build(question))
  end

  def code_question_change(values:) = Slack::Modals::CodeQuestionChange.values(values)

  def code_question_change_error(message) = { response_action: "errors", errors: { Slack::Modals::CodeQuestionChange::ANSWER_BLOCK => message } }

  # The build returns nil when there is nothing in the workspace to link to.
  def open_link_incident_modal(trigger_id:, incident:, private_metadata: nil, default_type: IncidentRelationship::RELATED)
    view = Slack::Modals::Link.build(incident, private_metadata: private_metadata, default_type: default_type)
    return unless view

    open_modal(trigger_id: trigger_id, view: view)
  end

  private

  def readable(text) = (messages_as_text(texts: [ text ])[text] if text.present?)
end
