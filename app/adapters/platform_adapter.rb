# Contract every platform-specific workspace adapter must satisfy.
#
# `WorkspaceAdapter.for(workspace)` returns a concrete subclass
# (`Slack::WorkspaceAdapter` today, `Teams::WorkspaceAdapter` planned).
# Services and workflows depend only on this contract, never on the
# concrete adapter class.
#
# Vocabulary:
#   - `channel_id` is an opaque platform-specific conversation identifier.
#   - `message_id` is an opaque platform-specific message identifier, Slack's
#     `ts`, a Teams message id, and so on.
#   - `parent_message_id` identifies the parent message when threading.
#   - `user_id` is an opaque platform-specific user identifier.
#   - `view` is an opaque platform-specific modal or form descriptor. Callers
#     obtain one from the platform's own `Modals::X.build(...)` helpers.
#
# Errors: every method raises `AdapterError` (or a subclass) when the
# platform call fails. Subclasses use `translate_errors` to convert
# platform-specific errors into the shared `AdapterError` hierarchy.
class PlatformAdapter
  class NotImplemented < NotImplementedError
    def initialize(method_name, adapter_class)
      super("#{adapter_class} must implement ##{method_name}")
    end
  end

  def initialize(workspace)
    @workspace = workspace
  end

  # Channel lifecycle

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

  # Messaging

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

  # The modals the app opens, by kind.
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

  # Builds the platform's view for a modal kind. Positional arguments are the
  # domain objects the modal shows (an incident, a runbook, a role list).
  # `metadata:` is an encoded ModalState carried back on submission.
  # @return [Object] an opaque view for open_modal, push_modal, update_modal
  #   or form_update_response
  def build_modal(kind, *args, metadata: nil, **options)
    raise NotImplemented.new(__method__, self.class)
  end

  # Reads a submitted incident form (declare, update, resolve, cancel) out of
  # the platform's submission payload.
  # @return [Object] responds to system_attrs, custom_fields, errors,
  #   first_error_field_key, includes_system_key?
  def parse_form_submission(form_slug:, values:, incident: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # The submission response that keeps the modal open and marks one field
  # (a system field key or a custom field key) with a message.
  # @return [Hash]
  def form_error_response(field_key, message)
    raise NotImplemented.new(__method__, self.class)
  end

  # The submission response that replaces the open modal with another view.
  # @return [Hash]
  def form_update_response(view)
    raise NotImplemented.new(__method__, self.class)
  end

  # Whether free text names people in the platform's own way (mentions,
  # handles, ids), so a command can decide between acting and opening a picker.
  # @return [Boolean]
  def people_targets?(text)
    raise NotImplemented.new(__method__, self.class)
  end

  # Turns mentions, handles and ids in free text into platform user ids.
  # @return [Hash] { user_ids: [String], unresolved_handles: [String], had_target_tokens: Boolean }
  def resolve_people(text)
    raise NotImplemented.new(__method__, self.class)
  end

  # Posts an approval request where approvers will see it.
  # @return [Hash] { message_id: String, channel_id: String }
  def post_approval_request(approval:, channel_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Posts an approval request to one person, outside any channel.
  # @return [Hash] { message_id: String, channel_id: String }
  def post_approval_request_to_user(approval:, user_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Rewrites a posted approval request once it is decided.
  # @return [Hash] { success: true }
  def mark_approval_resolved(approval:, channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Everyone the platform knows in this workspace, split into the ids it
  # returned as active and the ids it says are deactivated.
  # @return [Hash] { active_ids: Set, deactivated_ids: Set }
  def member_directory
    raise NotImplemented.new(__method__, self.class)
  end

  # A private message from Firefight to one person, outside any channel.
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

  # @return [Hash] { permalink: "https://..." }
  # A URL that opens the incident's channel in the platform's own client.
  # @return [String, nil] nil when the incident has no channel.
  def channel_url(channel_id:)
    raise NotImplementedError
  end

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
  def post_action_handed_over(channel_id:, action:, reassigned_by:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Posted when an item is handed to someone who has no message of their own to
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

  # Modals / forms

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

  # Tells the requester, privately, that a postmortem generation failed.
  # @return [Hash] { success: true }
  def post_postmortem_generation_failed(channel_id:, user_id:, incident:, reason:, retrying:)
    raise NotImplemented.new(__method__, self.class)
  end

  # Generated text

  # Prompt instruction describing the markup this platform renders.
  # @return [String]
  def ai_output_style
    raise NotImplemented.new(__method__, self.class)
  end

  # Users / directory

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
