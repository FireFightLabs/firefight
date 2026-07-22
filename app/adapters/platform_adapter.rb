# Contract every platform-specific workspace adapter must satisfy.
#
# `WorkspaceAdapter.for(workspace)` returns a concrete subclass
# (`Slack::WorkspaceAdapter` today, `Teams::WorkspaceAdapter` planned).
# Services and workflows depend only on this contract — never on the
# concrete adapter class.
#
# Vocabulary:
#   - `channel_id`     — opaque platform-specific conversation identifier
#   - `message_id`     — opaque platform-specific message identifier
#                        (Slack's `ts`, Teams's message id, etc.)
#   - `parent_message_id` — identifier of the parent message when threading
#   - `user_id`        — opaque platform-specific user identifier
#   - `view`           — opaque platform-specific modal/form descriptor;
#                        callers obtain one via the platform's own
#                        `Modals::X.build(...)` helpers
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

  # --- Channel lifecycle --------------------------------------------------

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

  # --- Messaging ----------------------------------------------------------

  # @return [Hash] { message_id: ... }
  def post_message(channel_id:, text:, blocks:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { message_id: ... }
  def post_threaded_message(channel_id:, parent_message_id:, text:, blocks: nil)
    raise NotImplemented.new(__method__, self.class)
  end

  # @return [Hash] { success: true }
  def post_ephemeral(channel_id:, user_id:, text:, blocks: nil)
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

  # @return [Hash] { ok: true }
  def pin_message(channel_id:, message_id:)
    raise NotImplemented.new(__method__, self.class)
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

  # @return [Hash] { success: true }
  def update_runbook_applied(channel_id:, message_id:, incident_runbook:)
    raise NotImplemented.new(__method__, self.class)
  end

  # --- Modals / forms -----------------------------------------------------

  # @param view [Hash] Opaque platform-specific view descriptor.
  # @return [Hash] { success: true }
  def open_modal(trigger_id:, view:)
    raise NotImplemented.new(__method__, self.class)
  end

  # @param view [Hash] Opaque platform-specific view descriptor.
  # @return [Hash] { success: true }
  def push_modal(trigger_id:, view:)
    raise NotImplemented.new(__method__, self.class)
  end

  # --- Users / directory --------------------------------------------------

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
