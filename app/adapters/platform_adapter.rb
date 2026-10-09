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

  # @return [Hash] { message_id: ..., channel_id: ... }
  def post_threaded_message(channel_id:, parent_message_id:, text:, blocks: nil)
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
  def post_approval_request(approval:, channel_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: String, channel_id: String }
  def post_approval_request_to_user(approval:, user_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def mark_approval_resolved(approval:, channel_id:, message_id:)
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

  # @return [Hash] { permalink: "https://..." }
  def get_message_permalink(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id:, channel_id:, user_id:, text:, posted_at:, raw: }
  def fetch_message(channel_id:, message_id:)
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
  # @return [Hash] { interval: ActiveSupport::Duration, max_chars: Integer }
  def agent_stream_cadence
    raise NotImplemented.new(__method__, self.class)
  end

  # How often a step's details, or a fix's progress message, may be redrawn while a long step works, in seconds.
  # @return [Integer]
  def agent_step_update_interval
    raise NotImplemented.new(__method__, self.class)
  end

  # Says an investigation has started, and opens the thread the rest of it goes in. incident is nil for a question
  # nobody has declared an incident for, which is then named by the question. Where the app cannot post, it goes to
  # fallback_user_id directly when one is given, and channel_id says where it went.
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_started(channel_id:, incident:, started_by:, question: nil, fallback_user_id: nil)
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

  # An answer given before its incident existed, posted in the channel of the incident declared from it.
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_carried_over(channel_id:, finding:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The answer, and the end of the working state.
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

  # A run's fix as it is applied, in the run's thread, with Mark done on each step a person does.
  # @return [Hash] { message_id:, channel_id: }
  def post_fix_progress(channel_id:, thread_id:, plan:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Redraws that message as the fix moves on.
  # @return [Hash] { success: true }
  def update_fix_progress(channel_id:, message_id:, plan:)
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

  # Opens the form that answers a coding agent's question.
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

  # Redraws a confirmation message once some of its calls are answered.
  # @return [Hash] { success: true }
  def update_agent_confirmation(channel_id:, message_id:, conversation_id:, confirmations:)
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

  # One line a watch Halon keeps said, such as a milestone or how it ended, in the chat's thread. update is a
  # Conversation::Watches::Said.
  # @return [Hash] { message_id:, channel_id: }
  def post_watch_update(channel_id:, thread_id:, update:)
    raise NotImplemented.new(__method__, self.class)
  end

  # The same line to whoever asked for the watch. conversation_id is the dashboard chat it reports to, which the message
  # offers to open, or nil for a chat that is not on the dashboard.
  # @return [Hash] { message_id:, channel_id: }
  def post_watch_update_to_user(user_id:, update:, conversation_id: nil)
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

  # Ends the working state with the reply. streamed means the person already read the text as it arrived.
  # @return [Hash] { message_id:, channel_id: }
  def post_agent_reply(channel_id:, thread_id:, answer_id:, text:, streamed: false)
    raise NotImplemented.new(__method__, self.class)
  end

  # Why the run stopped without an answer, and the end of the working state. rerun is the incident
  # to offer another run on, and rerun_question the run whose question to ask again when it had no
  # incident, each given only when running it again could end differently. investigation is the run,
  # so the message can link to it.
  # @return [Hash] { message_id:, channel_id: }
  def post_investigation_stopped(channel_id:, thread_id:, answer_id:, reason:, rerun: nil, rerun_question: nil, investigation: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # A file shared with a message, fetched from the platform. body is nil when it was too large to fetch or could not be,
  # and failure is then a sentence saying why, for whoever reads it to pass on.
  SharedFile = Data.define(:name, :byte_size, :body, :too_large, :failure)

  # The files shared with a message, as the platform's own event described them, which callers pass on unread. A file
  # over max_bytes is not downloaded.
  # @return [Array<PlatformAdapter::SharedFile>]
  def fetch_shared_files(files:, max_bytes:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { user_id:, display_name:, real_name:, avatar_url:, email:, timezone: }
  def get_user_info(user_id:)
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
