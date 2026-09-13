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
  def post_incident_update_announcement_thread(channel_id:, parent_message_id:, incident:, message:, updated_by_platform_user_id:, previous_status_name: nil, previous_severity_name: nil, previous_type_name: nil, subscriber_user_ids: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_resolution_announcement_thread(channel_id:, parent_message_id:, incident:, resolved_by_platform_user_id:, subscriber_user_ids: [])
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_reopen_announcement_thread(channel_id:, parent_message_id:, incident:, reopened_by_platform_user_id:, reason: nil, subscriber_user_ids: [])
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

  # @return [Hash] { success: true }
  def post_postmortem_generation_failed(channel_id:, user_id:, incident:, reason:, retrying:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Prompt instruction naming the markup this platform renders.
  # @return [String]
  def ai_output_style
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
