# Services and workflows depend on this contract, never on a concrete adapter.
# Every id and view is opaque to callers, and every method raises AdapterError on failure.
class PlatformAdapter
  class NotImplemented < NotImplementedError
    def initialize(method_name, adapter_class)
      super("#{adapter_class} must implement ##{method_name}")
    end
  end

  def initialize(workspace)
    @workspace = workspace
  end

  # @return [Hash] { channel_id:, channel_name: }
  def create_channel(name:, is_private: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def archive_channel(channel_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def unarchive_channel(channel_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def set_channel_topic(channel_id:, topic:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def set_channel_metadata(channel_id:, topic:, purpose:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { invited_user: user_id }
  def invite_user(channel_id:, user_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { invited_users: user_ids }
  def invite_users(channel_id:, user_ids:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ..., channel_id: ... }
  def post_message(channel_id:, text:, blocks:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A channel someone named, by its name, its id, a mention of it or its link, as the platform writes them.
  # Raises AdapterError::NotFound when Firefight cannot see it.
  # @return [Hash] { channel_id:, channel_name: }, channel_name nil when only the id is known.
  def find_channel(reference:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A message posted as Firefight in any channel at someone's request, naming who asked. by_halon says Halon wrote it
  # for them rather than an outside agent or a script. thread_id posts it as a reply in that thread.
  # @return [Hash] { message_id: ..., channel_id: ... }
  def post_channel_message(channel_id:, message:, posted_by:, by_halon:, thread_id: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # broadcast also shows the reply in the channel itself, for what everyone there should see.
  # @return [Hash] { message_id: ..., channel_id: ... }
  def post_threaded_message(channel_id:, parent_message_id:, text:, blocks: nil, broadcast: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def post_ephemeral(channel_id:, user_id:, text:, blocks: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Answers whoever pressed a button, only to them and where they pressed it, a thread included. The handle is the
  # token the platform attached to the press.
  # @return [Hash] { ok: true }
  def answer_privately(prompt_handle:, text:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Whether the control behind action_id shows what was pressed by itself, so a press needs no answer of its own.
  # @return [Boolean]
  def confirms_press_itself?(action_id)
    raise NotImplemented.new(__method__, self.class)
  end

  # Takes down an ephemeral prompt. The handle is the token the platform
  # attached to the button click, carried through the modal's metadata.
  # @return [Hash] { ok: true }
  def dismiss_prompt(prompt_handle:)
    raise NotImplemented.new(__method__, self.class)
  end

  module Modal
    INCIDENT_CREATION = :incident_creation
    INCIDENT_CREATED = :incident_created
    INCIDENT_UPDATE = :incident_update
    INCIDENT_CLOSE = :incident_close
    INCIDENT_CANCEL = :incident_cancel
    REOPEN = :reopen
    SUMMARY = :summary
    ESCALATE = :escalate
    INVITE = :invite
    LEAD = :lead
    ROLES = :roles
    ATTACH_RUNBOOK = :attach_runbook
    RUNBOOK_DETAIL = :runbook_detail
    ACTION_ITEMS_LIST = :action_items_list
    ACTION_ITEMS_FORM = :action_items_form
    SHOUTOUT = :shoutout
    HOME = :home
  end

  # What kind of answer one input of a submitted modal holds, for submitted_value.
  module Input
    TEXT = :text
    OPTION = :option
    USER = :user
    USERS = :users
    CONVERSATIONS = :conversations
  end

  # Positional arguments are the domain objects the modal shows. `metadata:` is
  # an encoded ModalState handed back on submission.
  # @return [Object] an opaque view for open_modal, push_modal, update_modal
  #   or form_update_response
  def build_modal(kind, *args, metadata: nil, **options)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Object] responds to system_attrs, custom_fields, errors,
  #   first_error_field_key, includes_system_key?
  def parse_form_submission(form_slug:, values:, incident: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps the modal open with a message on one field, system or custom.
  # @return [Hash]
  def form_error_response(field_key, message)
    raise NotImplemented.new(__method__, self.class)
  end

  # Replaces the open modal with another view.
  # @return [Hash]
  def form_update_response(view)
    raise NotImplemented.new(__method__, self.class)
  end

  # What a person gave in one input of a submitted modal, found by its Identifiers block and input ids. kind is an Input.
  # @return [String, Array<String>, nil] text, a choice's value or a person's id, a list for several, nil when left empty
  def submitted_value(values:, block_id:, input_id:, kind:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps the modal open with a message beside each refused input, keyed by the input's Identifiers block id.
  # @return [Hash]
  def modal_errors_response(errors)
    raise NotImplemented.new(__method__, self.class)
  end

  # Closes the submitted modal and every modal under it.
  # @return [Hash]
  def modal_close_response
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens another view on top of the submitted modal.
  # @return [Hash]
  def modal_push_response(view)
    raise NotImplemented.new(__method__, self.class)
  end

  # Whether free text names people (mentions, handles, ids), so a command can
  # choose between acting and opening a picker.
  # @return [Boolean]
  def people_targets?(text)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { user_ids: [String], unresolved_handles: [String], had_target_tokens: Boolean }
  def resolve_people(text)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: String, channel_id: String }
  def post_approval_request(approval:, channel_id:, shown:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: String, channel_id: String }
  def post_approval_request_to_user(approval:, user_id:, shown:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def mark_approval_resolved(approval:, channel_id:, message_id:, shown:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the call an approval request is for, its key, scope and parameters, which its card keeps off it.
  # @return [Hash] { success: true }
  def open_approval_details(trigger_id:, approval:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { active_ids: Set, deactivated_ids: Set }
  def member_directory
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def post_direct_message(user_id:, text:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def update_message(channel_id:, message_id:, text:, blocks:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def delete_message(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def add_reaction(channel_id:, message_id:, name:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Says in an incident's channel that someone is in the given dialog, doing what doing says ("escalating the incident").
  # @return [Hash] { message_id: String }
  def post_modal_placeholder(channel_id:, user_id:, modal:, doing:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: String }
  def post_summary_updated(channel_id:, updated_by_platform_user_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Shows one person a Firefight token minted for them, seen by them alone and gone once they reload, so the platform
  # keeps no copy either. title names what the token is for.
  # @return [Hash] { success: true }
  def post_token_once(user_id:, title:, token:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Tells one person why Halon will not do what they asked: in the thread they asked in, seen by them alone, and in their
  # direct messages, where it stays once they reload.
  # @return [Hash] { success: true }
  def post_refusal(channel_id:, thread_id:, user_id:, text:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param notice [PlatformAdapter::Notice]
  # @return [Hash] { success: true }
  def post_notice(user_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def remove_reaction(channel_id:, message_id:, name:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Shows on a person's message that Halon is working on it. Best effort, a refusal is logged and never raised.
  def mark_working(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Shows on a message Halon was working on that the answer is in, replacing mark_working. Best effort.
  # @return [Hash] { success:, retry: } success false when either mark did not change, and retry true only when the
  #   platform may still take it, so a message or channel it refused for good is never tried again
  def mark_done(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Takes mark_working off a message Halon will not answer, such as one it refused. Best effort.
  def unmark_working(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def pin_message(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [String] the connected team as the people running Firefight would recognise it, such as its address.
  def team_label
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [String, nil] nil when the incident has no channel.
  def channel_url(channel_id:)
    raise NotImplementedError
  end

  # @return [Hash] { permalink: "https://..." }, permalink nil when either id is blank.
  def get_message_permalink(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Nil when the platform answers with a message other than the one asked for, as it may for one that was deleted.
  # @return [Hash, nil] { message_id:, channel_id:, user_id:, text:, posted_at:, raw: }
  def fetch_message(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Messages as people wrote them on the platform, such as a quote on the timeline, as markdown the dashboard renders.
  # A mention reads as the person's name, and an emoji written by its name reads as the emoji.
  # @return [Hash{String => String}] each text given, mapped to its markdown.
  def messages_as_markdown(texts:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same messages as plain text, for a place that shows text as typed, such as a form field or a question in the
  # dashboard's chat. A mention reads as the person's name and an emoji as the emoji, and formatting marks drop away.
  # @return [Hash{String => String}] each text given, mapped to its plain text.
  def messages_as_text(texts:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same messages as a model is given them. A person or a channel is named with its platform id kept beside the
  # name, as "@Ana (U07ABC)", so the model can pass it to a tool, an emoji reads as the emoji and code keeps its marks.
  # @return [Hash{String => String}] each text given, mapped to the model's reading of it.
  def messages_for_model(texts:)
    raise NotImplemented.new(__method__, self.class)
  end

  # One message as a model is given it, read as messages_for_model reads it. Blank text comes back as given.
  # @return [String, nil]
  def message_for_model(text:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form for an action or a follow-up. A reaction's form opens empty when its state carries where the message
  # is, to be filled in by fill_in_action_item_modal.
  # @return [Hash] { success: true, view_id: } the open form, for filling it in.
  def open_action_item_modal(kind:, trigger_id:, incident:, private_metadata: nil, push: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # Reads the message a reaction's form was opened for and fills the open form in with it. Logs and returns nil when the
  # message cannot be read or the form has closed.
  def fill_in_action_item_modal(view_id:, kind:, incident:, private_metadata:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Asks the person who reacted to a message whether to make an action or a follow-up of it. The prompt quotes the
  # message, and its button carries where the message is, so the form reads the message when it opens.
  def post_action_from_reaction_prompt(channel_id:, user_id:, action_type:, message_id:, message_text:, incident_id:, source_message_link:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What a message mentioning the app says to it: its text in the platform's own markup with the app's own mention
  # taken out, and anyone else it mentions left where they are.
  # @return [String]
  def text_for_app(payload:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Whether a message event came from someone in another organisation, reached through a connection shared with it.
  # @return [Boolean]
  def sender_from_another_organisation?(payload:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The message a pin or unpin event is about, or nil when the pin is not on a message.
  # @return [Hash, nil] { channel_id:, message_id:, thread_id:, user_id: }
  def pinned_message(payload:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A reaction event: the emoji's name, the message it is on and who added it.
  # @return [Hash] { emoji:, channel_id:, message_id:, user_id: }
  def reaction(payload:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The app's own message a button was pressed on. content is the message as posted, handed back unread to the adapter
  # method that rewrites it.
  # @return [Hash] { channel_id:, message_id:, content: }
  def pressed_message(raw:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What started a thread in a person's direct messages with the app.
  THREAD_STARTED_BY_PERSON = :person
  # One of the app's own messages, such as a watch update, an approval or a question for its owner.
  THREAD_STARTED_BY_APP = :app
  # A new chat the person opened in the platform's own view for talking to the app, which the platform starts for them.
  THREAD_STARTED_AS_CHAT = :chat

  # @return [Hash] { started:, text: }, started one of the THREAD_STARTED_* values and text what the first message says.
  #   THREAD_STARTED_BY_PERSON with no text when the start cannot be read.
  def direct_thread_root(channel_id:, thread_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_runbook_message(channel_id:, incident_runbook:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param changes [Array<Hash>] [{ role_name:, platform_user_id: }], a nil
  #   platform_user_id meaning the role was cleared.
  # @return [Hash] { message_id: ... }
  def post_role_announcement(channel_id:, changes:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def update_runbook_message(channel_id:, message_id:, incident_runbook:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_action_message(channel_id:, action:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def update_action_picked_up(channel_id:, message_id:, action:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def update_action_completed(channel_id:, message_id:, action:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form that renames an action or a follow-up, on top of the one open when push is true.
  # @return [Hash] { success: true }
  def open_rename_action_modal(trigger_id:, action:, push: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # The new title a rename form was submitted with.
  # @return [String, nil]
  def renamed_action_title(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps a rename form open with why it was refused.
  # @return [Hash]
  def rename_action_error(message)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws an item's message as it now stands, after a change that did not come from its own controls, such as one
  # from its issue in a tracker.
  # @return [Hash] { success: true }
  def refresh_action_message(channel_id:, message_id:, action:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_action_handed_over(channel_id:, action:, reassigned_by:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Posted when an item is handed to someone with no message of their own to
  # act on. Becomes that item's message.
  # @return [Hash] { message_id: ... }
  def post_action_handover_notice(channel_id:, action:, reassigned_by:, link: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param link [IncidentAction::OriginReference, nil] where to look for context
  # @return [Hash] { message_id: ... }
  def post_action_completed(channel_id:, action:, completed_by:, link: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param result [IncidentInviteService::Result]
  # @return [Hash] { success: true }
  def post_invite_summary(channel_id:, user_id:, result:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param targets [Hash] { user_ids:, unresolved_handles:, had_target_tokens: }
  # @return [Hash] { success: true }
  def post_invite_unresolved(channel_id:, user_id:, targets:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param from [#actor_display_name] whoever is thanking
  # @param to [#actor_display_name, nil] whoever is being thanked
  # @return [Hash] { message_id: ... }
  def post_shoutout_message(channel_id:, incident:, from:, to:, message:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param stage [Integer] a WorkspaceOnboarding::STAGE_* value
  # @return [Hash] { message_id:, channel_id: }
  def post_welcome_message(channel_id:, stage:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param stage [Integer] a WorkspaceOnboarding::STAGE_* value
  # @return [Hash] { success: true }
  def update_welcome_message(channel_id:, message_id:, stage:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param step [Integer] STAGE_DECLARED to STAGE_DONE
  # @return [Hash] { message_id:, channel_id: }
  def post_first_incident_walkthrough(channel_id:, incident:, step:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param escalated_by [#actor_display_name] whoever asked
  # @param escalated_to [Incident::EscalationTarget] whoever was asked
  # @return [Hash] { message_id: ... }
  def post_escalation_message(channel_id:, incident:, escalated_by:, escalated_to:, reason: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param subscriber_user_ids [Array<String>] platform user ids to copy
  # @return [Hash] { message_id: ... }
  def post_escalation_announcement_thread(channel_id:, parent_message_id:, incident:, escalated_by:, escalated_to:, reason: nil, subscriber_user_ids: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id:, channel_id: }
  def post_incident_update_message(channel_id:, incident:, message:, updated_by_platform_user_id:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id:, channel_id: }
  def post_resolution_message(channel_id:, incident:, resolved_by_platform_user_id:, resolved_by_name: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id:, channel_id: }
  def post_reopen_message(channel_id:, incident:, reopened_by_platform_user_id:, reopened_by_name: nil, reason: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id:, channel_id: }
  def post_lead_announcement(channel_id:, lead_platform_user_id:, lead_name: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Tells the channel the lead could not be added to it, and how they can still join.
  # @return [Hash] { message_id:, channel_id: }
  def post_lead_invite_failed(channel_id:, lead_platform_user_id:, lead_name: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_incident_update_announcement_thread(channel_id:, parent_message_id:, incident:, message:, updated_by_platform_user_id:, updated_by_name: nil, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil, subscriber_user_ids: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_resolution_announcement_thread(channel_id:, parent_message_id:, incident:, resolved_by_platform_user_id:, resolved_by_name: nil, subscriber_user_ids: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_reopen_announcement_thread(channel_id:, parent_message_id:, incident:, reopened_by_platform_user_id:, reopened_by_name: nil, reason: nil, subscriber_user_ids: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # @param state [Symbol] one of Incident::Subscriptions::SUBSCRIBED, ALREADY_SUBSCRIBED, UNSUBSCRIBED
  # @return [Hash] { success: true }
  def post_subscription_notice(channel_id:, user_id:, incident:, state:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_escalation_direct_message(user_id:, incident:, escalated_by:, escalation_event_id:, reason: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_escalation_nudge_direct_message(user_id:, incident:, escalated_by:, escalation_event_id:, reason: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param view [Hash] Opaque platform-specific view descriptor.
  # @return [Hash] { success: true }
  def open_modal(trigger_id:, view:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param view [Hash] Opaque platform-specific view descriptor.
  # @return [Hash] { success: true }
  def update_modal(view_id:, view:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param view [Hash] Opaque platform-specific view descriptor.
  # @return [Hash] { success: true }
  def push_modal(trigger_id:, view:)
    raise NotImplemented.new(__method__, self.class)
  end

  # note is what to tell the person in place of the cause, when there is one.
  # @return [Hash] { success: true }
  def post_postmortem_generation_failed(channel_id:, user_id:, incident:, reason:, retrying:, note: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # The one reply /ff catchup posts in the incident's channel.
  # @return [Hash] { message_id: ..., channel_id: ... }
  def post_ai_response(channel_id:, incident:, answer:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Prompt instruction naming the markup this platform renders.
  # @return [String]
  def ai_output_style
    raise NotImplemented.new(__method__, self.class)
  end

  # Prompt instruction for streamed text, which can use different markup than a posted message.
  # @return [String]
  def ai_stream_output_style
    raise NotImplemented.new(__method__, self.class)
  end

  # How often streamed text may be sent, since each platform has its own rate limit.
  # whole_markup never cuts a link, bold or code across two pieces, for a platform that renders each piece's markup on its own.
  # @return [Hash] { interval: ActiveSupport::Duration, max_chars: Integer, whole_markup: Boolean }
  def agent_stream_cadence
    raise NotImplemented.new(__method__, self.class)
  end

  # How often a step's details, or a fix's progress message, may be redrawn while a long step works, in seconds.
  # @return [Integer]
  def agent_step_update_interval
    raise NotImplemented.new(__method__, self.class)
  end

  # Says an investigation has started with its checklist, and opens the thread the rest of it goes in. incident is nil
  # for a question nobody has declared an incident for, which is then named by the question. Where the app cannot post,
  # it goes to fallback_user_id directly when one is given, and channel_id says where it went.
  # @param progress [Investigation::Progress]
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_started(channel_id:, incident:, started_by:, progress:, question: nil, fallback_user_id: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws the message that started the run, in place, with its checklist as it stands. Nobody is notified.
  # @param progress [Investigation::Progress]
  # @return [Hash] { success: true }
  def update_investigation_progress(channel_id:, message_id:, incident:, started_by:, progress:, question: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Shows the agent as working, and opens whatever carries its steps.
  # @return [Hash] { answer_id: } where answer_id is nil when the platform has no live answer
  def start_agent_answer(channel_id:, thread_id:, user_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # One step the agent took, status is :running or :done. outcome is how a finished step went, a Chat::StepOutcome kind,
  # or nil when it is not known. details is one line on where a long step has got to, sent again as it moves.
  # @return [Hash] { success: true }
  def report_agent_step(channel_id:, answer_id:, key:, title:, status:, outcome: nil, details: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # An answer given before its incident existed, posted in the channel of the incident declared from it, with the full
  # answer under it.
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_carried_over(channel_id:, finding:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The answer, and the end of the working state: the short answer in the thread and where the whole channel sees it,
  # then the full answer in the thread only. message_id is the short answer's.
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_answer(channel_id:, thread_id:, answer_id:, finding:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Appends streamed text. Returns streaming false once the platform stops taking it, so the caller posts the whole answer.
  # @return [Hash] { streaming: true|false }
  def append_agent_text(channel_id:, answer_id:, text:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Ends an answer whose turn was lost partway. One that showed anything gets ending as its last line, and one that showed
  # nothing is removed.
  # @return [Hash] { success: true }
  def end_interrupted_answer(channel_id:, message_id:, shown:, ending:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Ends the working state by asking the person to confirm the calls the agent paused on.
  # @return [Hash] { message_id:, channel_id: }
  def ask_agent_confirmation(channel_id:, thread_id:, answer_id:, conversation_id:, confirmations:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws a posted answer, once its fix was applied.
  # @return [Hash] { success: true }
  def update_investigation_answer(channel_id:, message_id:, finding:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A fix's undo once Halon wrote it, in the run's thread, with its own way to apply it.
  # @return [Hash] { message_id:, channel_id: }
  def post_undo_plan(channel_id:, thread_id:, plan:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A run's fix as it is applied, in the run's thread and where the whole channel sees it, with Done on each step a
  # person does and Try again on each that failed. Posted once, and redrawn with how the fix ended rather than followed
  # by a second post.
  # @return [Hash] { message_id:, channel_id: }
  def post_fix_progress(channel_id:, thread_id:, plan:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws that message as the fix moves on.
  # @return [Hash] { success: true }
  def update_fix_progress(channel_id:, message_id:, plan:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What Halon did about a fix an unattended rule covers: that it applied it on its own, under which rule, what it read
  # and how to undo it, or why it did not act. In the thread when one is given, else in the channel.
  # @param note [Investigation::Unattended::Note]
  # @return [Hash] { message_id:, channel_id: }
  def post_unattended_note(channel_id:, thread_id:, note:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Says in an incident's channel that Halon did not start on the alert that opened it, and why. rerun offers a way to
  # start it by hand, for a reason that a person starting it gets past, such as the hour's spending ceiling.
  # @return [Hash] { message_id:, channel_id: }
  def post_alert_run_held(channel_id:, incident:, reason:, rerun:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Asks an incident's channel to decide on memories, each with the actions its state allows, in a thread when given.
  # post is a MemoryPostService::Shown.
  # @return [Hash] { message_id:, channel_id: }
  def post_learned_memories(channel_id:, thread_id:, post:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same, to one person directly, as a reminder of memories they or the team taught. channel_id is where it landed,
  # which a redraw needs.
  # @return [Hash] { message_id:, channel_id: }
  def post_learned_memories_to_user(user_id:, post:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws that message once someone decides on a memory it shows.
  # @return [Hash] { success: true }
  def update_learned_memories(channel_id:, message_id:, post:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form for Run it on a runbook attached to an incident, asking the questions its workflow's run asks. push
  # stacks it on a view already open, such as the runbook's detail.
  # @return [Hash] { success: true }
  def open_runbook_run_modal(trigger_id:, incident_runbook:, push: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # The answers a Run it form was submitted with, by each question's key.
  # @return [Hash] { key => value }
  def runbook_run_inputs(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Turns a Run it form into why the run did not start.
  # @return [Hash] the platform's answer to the form
  def runbook_run_refused(message)
    raise NotImplemented.new(__method__, self.class)
  end

  # Tells only the person who pressed Run it that the run started, with where to follow it.
  # @return [Hash]
  def post_runbook_run_started(channel_id:, user_id:, run:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form asking what is right instead of a memory. memory is a MemoryPostService::ShownMemory.
  # @return [Hash] { success: true }
  def open_memory_correction_modal(trigger_id:, post_id:, memory:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What a correction form was submitted with.
  # @return [Hash] { correction:, reason: }
  def memory_correction(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps a correction form open with why it was refused.
  # @return [Hash] the platform's answer to the form
  def memory_correction_error(message)
    raise NotImplemented.new(__method__, self.class)
  end

  # A handbook edit Halon proposed, with Accept, Edit and Dismiss, in a thread when given. proposal is a
  # HandbookProposalService::Shown.
  # @return [Hash] { message_id:, channel_id: }
  def post_handbook_proposal(channel_id:, thread_id:, proposal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws that message once someone decides on it.
  # @return [Hash] { success: true }
  def update_handbook_proposal(channel_id:, message_id:, proposal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A skill Halon proposed, with Accept and Dismiss and the Skills page to edit it first, in a thread when given. proposal
  # is a SkillProposalService::Shown.
  # @return [Hash] { message_id:, channel_id: }
  def post_skill_proposal(channel_id:, thread_id:, proposal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws that message once someone decides on it, here or on the Skills page.
  # @return [Hash] { success: true }
  def update_skill_proposal(channel_id:, message_id:, proposal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form for editing a proposed handbook edit before accepting it.
  # @return [Hash] { success: true }
  def open_handbook_proposal_modal(trigger_id:, proposal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The wording an edit form was submitted with.
  # @return [String]
  def handbook_proposal_text(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps an edit form open with why it was refused.
  # @return [Hash] the platform's answer to the form
  def handbook_proposal_error(message)
    raise NotImplemented.new(__method__, self.class)
  end

  # A coding agent's question, in the thread of the chat or fix its change was asked in, with Answer while it waits.
  # question is a CodeAgentQuestion.
  # @return [Hash] { message_id:, channel_id: }
  def post_code_question(channel_id:, thread_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once it is answered, or ended unanswered.
  # @return [Hash] { success: true }
  def update_code_question(channel_id:, message_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A code change paused at its spending limit, asking whether to continue, with Continue and Stop, in the thread of the
  # chat or run it came from. pause is a CodeAgentSession::Pause.
  # @return [Hash] { message_id:, channel_id: }
  def post_code_pause(channel_id:, thread_id:, pause:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same, in a direct message to whoever asked, when the run it came from has no thread. channel_id is the direct
  # message conversation, where Continue carries the change on under this message.
  # @return [Hash] { message_id:, channel_id: }
  def post_code_pause_to_user(user_id:, pause:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once someone decided.
  # @return [Hash] { success: true }
  def update_code_pause(channel_id:, message_id:, pause:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A workflow's question, in a direct message to someone it asked, with a button per choice and Answer for its form.
  # question is a Workflow::Run::Question.
  # @return [Hash] { message_id:, channel_id: }
  def post_workflow_question(user_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A Manual step's task given to anyone, posted in a channel with Done.
  # @return [Hash] { message_id:, channel_id: }
  def post_workflow_question_in_channel(channel_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once it is answered or withdrawn.
  # @return [Hash] { success: true }
  def update_workflow_question(channel_id:, message_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form that answers a workflow's question.
  # @return [Hash] { success: true }
  def open_workflow_question_modal(trigger_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What the form was submitted with.
  # @return [Hash] { choice: String or nil, values: Hash of field name to text }
  def workflow_question_answer(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps the form open with why the answer was refused.
  # @return [Hash] the platform's answer to the form
  def workflow_question_error(message, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form that answers a coding agent's question.
  # @return [Hash] { success: true }
  def open_code_question_modal(trigger_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What the answer form was submitted with.
  # @return [String] the answer
  def code_question_answer(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps the answer form open with why it was refused.
  # @return [Hash] the platform's answer to the form
  def code_question_error(message)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the form that changes the answer to a coding agent's settled question.
  # @return [Hash] { success: true }
  def open_code_question_change_modal(trigger_id:, question:)
    raise NotImplemented.new(__method__, self.class)
  end

  # What the change form was submitted with: the option picked, by its index, or nil, and the person's own words.
  # @return [#option, #answer]
  def code_question_change(values:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Keeps the change form open with why it was refused.
  # @return [Hash] the platform's answer to the form
  def code_question_change_error(message)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws a confirmation message once some of its calls are answered.
  # @return [Hash] { success: true }
  def update_agent_confirmation(channel_id:, message_id:, conversation_id:, confirmations:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens everything a request to approve a change keeps off its card. confirmation is a Chat::Tools::Confirmation.
  # @return [Hash] { success: true }
  def open_agent_confirmation_details(trigger_id:, confirmation:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A call the agent made in a chat that an approval rule held, once someone decided on it, in the chat's thread, with
  # Run and Dismiss while it waits for the person who asked. held_call is a Conversation::HeldCalls::Shown.
  # @return [Hash] { message_id:, channel_id: }
  def post_held_call(channel_id:, thread_id:, held_call:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same, to whoever asked, for a chat that lives on the dashboard, with a way to open it there.
  # @return [Hash] { message_id:, channel_id: }
  def post_held_call_to_user(user_id:, held_call:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws either as the call moves on. direct is the message to whoever asked rather than the one in the thread.
  # @return [Hash] { success: true }
  def update_held_call(channel_id:, message_id:, held_call:, direct: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # Opens the held call as it was given, which its message keeps off it. held_call is a Conversation::HeldCalls::Shown.
  # @return [Hash] { success: true }
  def open_held_call_details(trigger_id:, held_call:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The one card a watch Halon keeps has in a place, posted once: in a chat's thread, or to a person's direct messages
  # when thread_id is nil and channel_id is their user id. card is a Conversation::Watches::Card.
  # @return [Hash] { message_id:, channel_id: }
  def post_watch_card(channel_id:, thread_id:, card:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws a watch's card where it was posted, from how the watch stands now.
  # @return [Hash] { success: true }
  def update_watch_card(channel_id:, message_id:, card:)
    raise NotImplemented.new(__method__, self.class)
  end

  # How a watch ended, as a short message of its own beside its card, so the person is told. Placed as post_watch_card.
  # @return [Hash] { message_id:, channel_id: }
  def post_watch_end(channel_id:, thread_id:, card:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A plan Halon keeps for a chat, as a checklist, in the chat's thread. plan is a Chat::Plan.
  # @return [Hash] { message_id:, channel_id: }
  def post_chat_plan(channel_id:, thread_id:, plan:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same to the person a dashboard chat belongs to, once a plan has a time they approved. conversation_id is the
  # chat, which the message offers to open.
  # @return [Hash] { message_id:, channel_id: }
  def post_chat_plan_to_user(user_id:, plan:, conversation_id: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it where it was posted as it moves. direct and conversation_id are as it was first sent with.
  # @return [Hash] { success: true }
  def update_chat_plan(channel_id:, message_id:, plan:, direct: false, conversation_id: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # A line about a temporary change Halon made, such as the reminder before Firefight undoes it, in the chat's thread.
  # notice is a Conversation::Mitigations::Notice.
  # @return [Hash] { message_id:, channel_id: }
  def post_mitigation_notice(channel_id:, thread_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same line to whoever asked for the change, offering to open the chat when it is on the dashboard.
  # @return [Hash] { message_id:, channel_id: }
  def post_mitigation_notice_to_user(user_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws a line about a temporary change where it was posted, such as once it was kept or undone.
  # @return [Hash] { success: true }
  def update_mitigation_notice(channel_id:, message_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Asks whoever started something, in their direct messages, whether Halon may stop it. ask is a
  # Conversation::OwnerAsks::Shown.
  # @return [Hash] { message_id:, channel_id: }
  def post_owner_ask(user_id:, ask:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws the ask once it was answered or is no longer needed.
  # @return [Hash] { success: true }
  def update_owner_ask(channel_id:, message_id:, ask:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A problem Halon found on its own, from a scheduled check, said in the channel of the team that owns it. notice is an
  # Investigation::Notice, said once and again only when it got worse.
  # @return [Hash] { message_id:, channel_id: }
  def post_monitoring_notice(channel_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A pull request Halon opened that needs attention, with why and Fix it, in the thread of the chat or run it came
  # from. notice is a CodeAgentSession::Notice.
  # @return [Hash] { message_id:, channel_id: }
  def post_pull_request_notice(channel_id:, thread_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same to whoever asked for the change, for a chat with no thread. conversation_id is the dashboard chat, which
  # the message offers to open.
  # @return [Hash] { message_id:, channel_id: }
  def post_pull_request_notice_to_user(user_id:, notice:, conversation_id: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once Fix it was pressed or the pull request moved on.
  # @return [Hash] { success: true }
  def update_pull_request_notice(channel_id:, message_id:, notice:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Whether a conversation's channel is a direct one with a single person, where a message to that person would land
  # twice.
  # @return [Boolean]
  def direct_conversation?(channel_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A change the agent was refused in a chat's thread for want of a pack, naming the pack and the admins, with Ask an
  # admin. refusal is a Chat::PackRefusal.
  # @return [Hash] { message_id:, channel_id: }
  def post_pack_refusal(channel_id:, thread_id:, refusal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once the admins were asked or the pack was given.
  # @return [Hash] { success: true }
  def update_pack_refusal(channel_id:, message_id:, refusal:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A secret a tool call in a chat's thread handed to the person who asked, pointing to the card in the dashboard where
  # it is typed or revealed, never asking for it here. entry is a Chat::SecretEntry.
  # @return [Hash] { message_id:, channel_id: }
  def post_secret_entry(channel_id:, thread_id:, entry:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once the value was set.
  # @return [Hash] { success: true }
  def update_secret_entry(channel_id:, message_id:, entry:)
    raise NotImplemented.new(__method__, self.class)
  end

  # How an admin answered a member's request for a pack, to that member. pack_request is an Ability::PackRequest.
  # @return [Hash] { message_id:, channel_id: }
  def post_pack_answer_to_user(user_id:, pack_request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same as a short note in the thread of a chat where the change was refused.
  # @return [Hash] { message_id:, channel_id: }
  def post_pack_answer(channel_id:, thread_id:, pack_request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A member's request for a pack, to one admin, with Give pack. pack_request is an Ability::PackRequest.
  # @return [Hash] { message_id:, channel_id: }
  def post_pack_request_to_user(user_id:, pack_request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once the pack was given or the request dismissed.
  # @return [Hash] { success: true }
  def update_pack_request(channel_id:, message_id:, pack_request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A member's request to publish a workflow, to one admin, with Publish. request is a Workflow::PublishRequest.
  # @return [Hash] { message_id:, channel_id: }
  def post_workflow_publish_request_to_user(user_id:, request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it once the workflow was published or the request dismissed.
  # @return [Hash] { success: true }
  def update_workflow_publish_request(channel_id:, message_id:, request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # How an admin answered a member's request to publish a workflow, to that member.
  # @return [Hash] { message_id:, channel_id: }
  def post_workflow_publish_answer_to_user(user_id:, request:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A workflow run that failed, with why, in the channel of the team that owns the workflow or to whoever published it.
  # suggestion says Halon suggested a fix on the run's page. channel_id may be a person's id for their direct messages.
  # @return [Hash] { message_id:, channel_id: }
  def post_workflow_failure(channel_id:, run:, suggestion:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A workflow Halon made from a chat, in that chat's thread, with Run now and Cancel.
  # @return [Hash] { message_id:, channel_id: }
  def post_chat_workflow(channel_id:, thread_id:, workflow:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws it as the workflow moves.
  # @return [Hash] { success: true }
  def update_chat_workflow(channel_id:, message_id:, workflow:)
    raise NotImplemented.new(__method__, self.class)
  end

  # One line saying a workflow ran and found nothing, for a workflow that asked for it.
  # @return [Hash] { message_id:, channel_id: }
  def post_workflow_all_clear(channel_id:, run:)
    raise NotImplemented.new(__method__, self.class)
  end

  # A fix's step that was approved, declined or expired, to whoever applied the fix when the fix has no thread to follow.
  # @return [Hash] { message_id:, channel_id: }
  def post_fix_step_to_user(user_id:, step:)
    raise NotImplemented.new(__method__, self.class)
  end

  # One category of integrations under an agent's answer, each with a way to connect it on the dashboard.
  # @param card [IntegrationProvider::Card]
  # @return [Hash] { message_id:, channel_id: }
  def post_integration_card(channel_id:, thread_id:, card:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Charts under an agent's answer, each as an image with its numbers and a link to the live chart. A workspace that has
  # not granted the permission to post images gets the numbers and the link as text, so nothing is lost.
  # @param charts [Array<Chat::Chart::Post>]
  # @return [Array<Hash>] { message_id:, channel_id: } per chart, message_id nil for an uploaded image
  def post_charts(channel_id:, thread_id:, charts:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Pages Halon's browser saw, under an agent's answer, each as an image with a line saying what it shows. A workspace
  # that has not granted the permission to post images gets the line alone. left_out says how many more were taken than
  # are posted, so a thread never quietly misses one.
  # @param screenshots [Array<Chat::Screenshot::Post>]
  # @return [Array<Hash>] { message_id:, channel_id: } per screenshot, message_id nil for an uploaded image
  def post_screenshots(channel_id:, thread_id:, screenshots:, left_out: 0)
    raise NotImplemented.new(__method__, self.class)
  end

  # Ends the working state with the reply. streamed means the person already read the text as it arrived. sources are
  # what Halon read to give it (Chat::Sources::Source), shown compactly under it.
  # @return [Hash] { message_id:, channel_id: }
  def post_agent_reply(channel_id:, thread_id:, answer_id:, text:, streamed: false, sources: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # Why the run stopped without an answer, and the end of the working state. rerun is the incident
  # to offer another run on, and rerun_question the run whose question to ask again when it had no
  # incident, each given only when running it again could end differently. investigation is the run,
  # so the message can link to it.
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_stopped(channel_id:, thread_id:, answer_id:, reason:, where_it_stopped: nil, rerun: nil, rerun_question: nil, investigation: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # A file shared with a message, fetched from the platform. body is nil when it was too large to fetch or could not be,
  # and failure is then a sentence saying why, for whoever reads it to pass on.
  SharedFile = Data.define(:name, :byte_size, :body, :too_large, :failure)

  # Something an admin needs to know and act on, sent to them directly: what happened as the title, what it means as the
  # body, and where to fix it as a link. link_url may be nil, when the place is named in the body instead. fallback is the
  # whole notice as one sentence, for a notification.
  Notice = Data.define(:title, :body, :link_label, :link_url, :fallback)

  # The files shared with a message, as the platform's own event described them, which callers pass on unread. A file
  # over max_bytes is not downloaded.
  # @return [Array<PlatformAdapter::SharedFile>]
  def fetch_shared_files(files:, max_bytes:)
    raise NotImplemented.new(__method__, self.class)
  end

  # email_confirmed says the platform confirmed the person holds the email.
  # @return [Hash] { user_id:, display_name:, real_name:, avatar_url:, email:, email_confirmed:, timezone: }
  def get_user_info(user_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Why a person the platform describes may not act through Firefight, such as a guest or someone from another
  # organisation, in words for them, or nil for one of the workspace's own. profile is what get_user_info answered, or
  # the same saved.
  # @return [String, nil]
  def member_refusal(profile:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Array<Hash>] [{ id:, name:, avatarUrl: }]
  def list_members
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Array<Hash>] [{ id:, name: }]
  def list_channels
    raise NotImplemented.new(__method__, self.class)
  end
end
