module Slack
  class WorkspaceAdapter < ::PlatformAdapter
    include Slack::WorkspaceAdapter::WorkspaceSetup
    include Slack::WorkspaceAdapter::UserOperations
    include Slack::WorkspaceAdapter::IncidentModals
    include Slack::WorkspaceAdapter::IncidentMessaging
    include Slack::WorkspaceAdapter::WorkflowMessaging
    include Slack::WorkspaceAdapter::FileOperations

    CHANNEL_DESCRIPTION = "Firefight announcements channel. Every time someone declares an incident, we'll announce it here, and make sure the post is always up to date."

    def create_channel(name:, is_private: false)
      translate_errors do
        result = Slack::Client.create_channel(
          workspace: @workspace,
          name: name,
          is_private: is_private
        )

        {
          channel_id: result[:channel][:id],
          channel_name: result[:channel][:name]
        }
      end
    end

    def archive_channel(channel_id:)
      translate_errors do
        Slack::Client.archive_channel(workspace: @workspace, channel: channel_id)
        { success: true }
      end
    end

    def unarchive_channel(channel_id:)
      translate_errors do
        Slack::Client.unarchive_channel(workspace: @workspace, channel: channel_id)
        { success: true }
      end
    end

    def set_channel_topic(channel_id:, topic:)
      translate_errors do
        Slack::Client.set_channel_topic(
          workspace: @workspace,
          channel: channel_id,
          topic: topic
        )

        { success: true }
      end
    end

    def set_channel_metadata(channel_id:, topic:, purpose:)
      translate_errors do
        Slack::Client.set_channel_topic(
          workspace: @workspace,
          channel: channel_id,
          topic: topic
        )

        Slack::Client.set_channel_purpose(
          workspace: @workspace,
          channel: channel_id,
          purpose: purpose
        )

        { success: true }
      end
    end

    def post_approval_request(approval:, channel_id:, shown:)
      with_rich_blocks do |rich|
        post_message(
          channel_id: channel_id,
          text: Slack::Messages::Approval.request_fallback(approval, shown: shown),
          blocks: Slack::Messages::Approval.build_request(approval, shown: shown, rich: rich)
        )
      end
    end

    # A user id as channel opens or reuses the DM with them.
    def post_approval_request_to_user(approval:, user_id:, shown:)
      post_approval_request(approval: approval, channel_id: user_id, shown: shown)
    end

    def mark_approval_resolved(approval:, channel_id:, message_id:, shown:)
      with_rich_blocks do |rich|
        update_message(
          channel_id: channel_id,
          message_id: message_id,
          text: Slack::Messages::Approval.resolved_fallback(approval, shown: shown),
          blocks: Slack::Messages::Approval.build_resolved(approval, shown: shown, rich: rich)
        )
      end
    end

    def open_approval_details(trigger_id:, approval:)
      open_modal(trigger_id: trigger_id, view: Slack::Modals::ApprovalDetails.build(approval, params: params_shown(approval)))
    end

    # A command typed in Slack is quoted as Slack shows it, so a mention or a broadcast in it never notifies again.
    def params_shown(approval)
      text = approval.platform_text
      approval.params_shown(text ? messages_as_text(texts: [ text ]) : {})
    end
    private :params_shown

    def post_message(channel_id:, text:, blocks:)
      translate_errors do
        result = Slack::Client.post_message(
          workspace: @workspace,
          channel: channel_id,
          text: text,
          blocks: blocks
        )

        { message_id: result[:ts], channel_id: result[:channel] }
      end
    end

    # Slack writes a channel in a message as <#C123|name>, and its link ends in /archives/C123. A private channel is
    # never listed to the app, so it is found only by its id, its mention or its link.
    CHANNEL_MENTION = /\A<#([CG][A-Z0-9]+)(?:\|([^>]*))?>\z/
    CHANNEL_LINK = %r{\Ahttps://[a-z0-9.-]+\.slack\.com/archives/([CG][A-Z0-9]+)}i
    CHANNEL_ID = /\A[CG][A-Z0-9]{8,}\z/

    def find_channel(reference:)
      text = reference.to_s.strip
      id, named = channel_reference(text)
      channels = list_channels
      if id
        listed = channels.find { |channel| channel[:id] == id }
        return { channel_id: id, channel_name: listed&.dig(:name) || named.presence }
      end

      wanted = text.delete_prefix("#").downcase
      found = channels.find { |channel| channel[:name].to_s.downcase == wanted }
      raise AdapterError::NotFound, "no channel named #{wanted}" unless found

      { channel_id: found[:id], channel_name: found[:name] }
    end

    def post_channel_message(channel_id:, message:, posted_by:, by_halon:, thread_id: nil)
      text = Slack::Messages::ChannelPost.fallback(message, by_halon: by_halon)
      blocks = Slack::Messages::ChannelPost.build(message, posted_by: posted_by, by_halon: by_halon)
      return post_threaded_message(channel_id: channel_id, parent_message_id: thread_id, text: text, blocks: blocks) if thread_id.present?

      post_message(channel_id: channel_id, text: text, blocks: blocks)
    end

    def add_reaction(channel_id:, message_id:, name:)
      translate_errors do
        Slack::Client.add_reaction(
          workspace: @workspace,
          channel: channel_id,
          timestamp: message_id,
          name: name
        )

        { success: true }
      end
    end

    def remove_reaction(channel_id:, message_id:, name:)
      translate_errors do
        Slack::Client.remove_reaction(
          workspace: @workspace,
          channel: channel_id,
          timestamp: message_id,
          name: name
        )

        { success: true }
      end
    end

    def mark_working(channel_id:, message_id:)
      quietly(:mark_working) { add_reaction(channel_id: channel_id, message_id: message_id, name: Slack::Emoji::REACTION_WORKING) }
    end

    # Each step on its own, so a message whose first mark is already gone still gets the second.
    def mark_done(channel_id:, message_id:)
      removed = unmark_working(channel_id: channel_id, message_id: message_id)
      added = quietly(:mark_done) { add_reaction(channel_id: channel_id, message_id: message_id, name: Slack::Emoji::REACTION_DONE) }
      { success: removed[:success] && added[:success] }
    end

    def unmark_working(channel_id:, message_id:)
      quietly(:unmark_working) { remove_reaction(channel_id: channel_id, message_id: message_id, name: Slack::Emoji::REACTION_WORKING) }
    end

    def pin_message(channel_id:, message_id:)
      translate_errors do
        Slack::Client.pin_message(
          workspace: @workspace,
          channel: channel_id,
          timestamp: message_id
        )

        { success: true }
      end
    end

    def invite_user(channel_id:, user_id:)
      translate_errors do
        Slack::Client.invite_to_channel(
          workspace: @workspace,
          channel: channel_id,
          users: user_id
        )

        { invited_user: user_id }
      end
    end

    def invite_users(channel_id:, user_ids:)
      translate_errors do
        Slack::Client.invite_to_channel(
          workspace: @workspace,
          channel: channel_id,
          users: user_ids
        )

        { invited_users: user_ids }
      end
    end

    def open_modal(trigger_id:, view:)
      translate_errors do
        Slack::Client.open_modal(
          workspace: @workspace,
          trigger_id: trigger_id,
          view: view
        )

        { success: true }
      end
    end

    def push_modal(trigger_id:, view:)
      translate_errors do
        Slack::Client.push_modal(
          workspace: @workspace,
          trigger_id: trigger_id,
          view: view
        )

        { success: true }
      end
    end

    def update_message(channel_id:, message_id:, text:, blocks:)
      translate_errors do
        Slack::Client.update_message(
          workspace: @workspace,
          channel: channel_id,
          ts: message_id,
          text: text,
          blocks: blocks
        )

        { success: true }
      end
    end

    def delete_message(channel_id:, message_id:)
      translate_errors do
        Slack::Client.delete_message(
          workspace: @workspace,
          channel: channel_id,
          ts: message_id
        )

        { success: true }
      end
    end

    def team_label
      team = @workspace.platform_data || {}
      return "#{team["domain"]}.slack.com" if team["domain"].present?

      team["name"].presence || @workspace.platform_id
    end

    # A deep link carrying the team, otherwise a browser signed into several
    # workspaces opens the last used one, where the channel does not exist.
    def channel_url(channel_id:)
      return nil if channel_id.blank?

      "slack://channel?team=#{@workspace.platform_id}&id=#{channel_id}"
    end

    # A message is named by both, so without either there is nothing to link and Slack is not asked.
    def get_message_permalink(channel_id:, message_id:)
      return { permalink: nil } if channel_id.blank? || message_id.blank?

      translate_errors do
        result = Slack::Client.get_permalink(
          workspace: @workspace,
          channel: channel_id,
          message_ts: message_id
        )

        { permalink: result[:permalink] }
      end
    end

    def fetch_message(channel_id:, message_id:)
      translate_errors do
        raw = Slack::Client.get_message(
          workspace: @workspace,
          channel: channel_id,
          ts: message_id
        )
        message = raw.is_a?(Hash) ? (raw[:message] || raw["message"] || raw) : {}
        # Slack hands back the newest message at or before the one asked for, so a deleted message reads as an older one.
        next unless (message[:ts] || message["ts"]) == message_id

        {
          message_id: message[:ts] || message["ts"],
          channel_id: channel_id,
          user_id: message[:user] || message["user"],
          text: message[:text] || message["text"],
          posted_at: (message[:ts] || message["ts"])&.to_f&.then { |t| Time.at(t) },
          raw: message
        }
      end
    end

    def message_for_model(text:) = text.present? ? messages_for_model(texts: [ text ])[text] : text

    def messages_as_markdown(texts:)
      names = mentioned_names(texts)
      texts.to_h { |text| [ text, Slack::MessageMarkdown.convert(text, names: names) ] }
    end

    def messages_as_text(texts:)
      names = mentioned_names(texts)
      texts.to_h { |text| [ text, Slack::MessageText.convert(text, names: names) ] }
    end

    def messages_for_model(texts:)
      names = mentioned_names(texts)
      texts.to_h { |text| [ text, Slack::MessageText.convert(text, names: names, for_model: true) ] }
    end

    # The app is known only by the user id Slack names in the event's authorizations, since the install keeps none. An
    # event without them keeps every mention, as guessing which one is the app could drop someone else.
    # People in an organisation wide install come from each of its workspaces, so the team is only compared for a single
    # workspace.
    def sender_from_another_organisation?(payload:)
      team = payload.dig("event", "user_team").presence
      team.present? && payload["enterprise_id"].blank? && team != payload["team_id"]
    end

    def pinned_message(payload:)
      event = payload["event"] || {}
      return unless event.dig("item", "type") == "message"

      { channel_id: event.dig("item", "channel"), message_id: event.dig("item", "message", "ts") || event.dig("item", "ts"),
        thread_id: event.dig("item", "message", "thread_ts"), user_id: event["user"] }
    end

    def reaction(payload:)
      event = payload["event"] || {}
      { emoji: event["reaction"], channel_id: event.dig("item", "channel"), message_id: event.dig("item", "ts"), user_id: event["user"] }
    end

    def pressed_message(raw:)
      { channel_id: raw&.dig("container", "channel_id"), message_id: raw&.dig("container", "message_ts"), content: raw&.dig("message", "blocks") || [] }
    end

    def text_for_app(payload:)
      text = payload.dig("event", "text").to_s
      app_ids = Array(payload["authorizations"]).filter_map { |authorization| authorization["user_id"] if authorization["is_bot"] }
      return text.squish if app_ids.empty?

      text.gsub(/<@(?:#{app_ids.map { |id| Regexp.escape(id) }.join('|')})(?:\|[^<>]*)?>/, "").squish
    end

    # Names come from Firefight's own members in one query, so a page of messages never calls Slack.
    def mentioned_names(texts)
      ids = texts.flat_map { |text| Slack::MessageMarkdown.mentioned_ids(text) }.uniq
      return {} if ids.empty?

      @workspace.workspace_memberships.where(platform_user_id: ids).includes(:user).to_h { |member| [ member.platform_user_id, member.display_name ] }
    end
    private :mentioned_names

    # The root of a thread Slack starts when someone opens a new chat in the app's agent view.
    AGENT_THREAD_SUBTYPE = "assistant_app_thread".freeze

    # Read from the thread's first message. One that cannot be read, or is not there any more, counts as the person's,
    # so their message is answered rather than dropped.
    def direct_thread_root(channel_id:, thread_id:)
      root = fetch_message(channel_id: channel_id, message_id: thread_id)&.dig(:raw).to_h.with_indifferent_access
      return { started: PlatformAdapter::THREAD_STARTED_BY_PERSON, text: nil } if root.empty?

      { started: thread_started_by(root), text: root[:text].presence }
    rescue AdapterError => error
      Rails.logger.info({ event: "slack.direct_thread_root.unread", error: error.class.name }.to_json)
      { started: PlatformAdapter::THREAD_STARTED_BY_PERSON, text: nil }
    end

    def thread_started_by(root)
      return PlatformAdapter::THREAD_STARTED_AS_CHAT if root[:subtype] == AGENT_THREAD_SUBTYPE
      return PlatformAdapter::THREAD_STARTED_BY_APP if root[:bot_id].present? || root[:app_id].present?

      PlatformAdapter::THREAD_STARTED_BY_PERSON
    end
    private :thread_started_by

    def get_user_info(user_id:)
      translate_errors do
        raw = Slack::Client.get_user_info(workspace: @workspace, user_id: user_id)
        user = raw[:user] || raw["user"] || raw
        profile = user[:profile] || user["profile"] || {}

        {
          user_id: user[:id] || user["id"],
          display_name: profile[:display_name].presence || profile["display_name"].presence || user[:name] || user["name"],
          real_name: profile[:real_name] || profile["real_name"],
          avatar_url: profile[:image_192] || profile["image_192"] || profile[:image_48] || profile["image_48"],
          email: profile[:email] || profile["email"],
          timezone: user[:tz] || user["tz"],
          raw: user
        }
      end
    end

    # broadcast also shows the reply in the channel itself.
    def post_threaded_message(channel_id:, parent_message_id:, text:, blocks: nil, broadcast: false)
      translate_errors do
        posting = { workspace: @workspace, channel: channel_id, text: text, blocks: blocks, thread_ts: parent_message_id }
        posting[:reply_broadcast] = true if broadcast
        result = Slack::Client.post_message(**posting)

        { message_id: result[:ts], channel_id: result[:channel] || channel_id }
      end
    end

    def post_ephemeral(channel_id:, user_id:, text:, blocks: nil)
      translate_errors do
        Slack::Client.post_ephemeral(
          workspace: @workspace,
          channel: channel_id,
          user: user_id,
          text: text,
          blocks: blocks
        )

        { success: true }
      end
    end

    def dismiss_prompt(prompt_handle:)
      translate_errors do
        Slack::Client.delete_original_response(response_url: prompt_handle)
      end
    end

    def answer_privately(prompt_handle:, text:)
      translate_errors do
        Slack::Client.respond_ephemerally(response_url: prompt_handle, text: text)
      end
    end

    # Slack's feedback thumbs show what was pressed themselves. A plain button does not.
    def confirms_press_itself?(action_id) = action_id == Identifiers::INVESTIGATION_FEEDBACK

    def self.refresh_expiring_credentials(buffer:)
      Slack::TokenManager.new.refresh_all_expiring(buffer: buffer)
    end

    def people_targets?(text)
      Slack::HandleResolver.target_tokens?(text)
    end

    def resolve_people(text)
      Slack::HandleResolver.new(@workspace).resolve(text)
    end

    # A user id as channel opens or reuses the DM with them.
    # Each on its own, so a direct message the person closed still leaves the note in the thread.
    def post_refusal(channel_id:, thread_id:, user_id:, text:)
      quietly(:refusal_in_thread) do
        translate_errors { Slack::Client.post_ephemeral(workspace: @workspace, channel: channel_id, user: user_id, text: text, thread_ts: thread_id) }
      end
      translate_errors do
        Slack::Client.post_message(workspace: @workspace, channel: user_id, text: text, blocks: Slack::Messages::Refusal.build(text, channel_id: channel_id))
      end
      { success: true }
    end

    def post_notice(user_id:, notice:)
      translate_errors do
        Slack::Client.post_message(workspace: @workspace, channel: user_id, text: notice.fallback, blocks: Slack::Messages::Notice.build(notice))
        { success: true }
      end
    end

    def post_direct_message(user_id:, text:)
      translate_errors do
        Slack::Client.post_message(workspace: @workspace, channel: user_id, text: text)
        { success: true }
      end
    end

    # Someone in neither set was not returned by Slack, which is not the same
    # as deactivated, so a caller may keep them.
    def member_directory
      translate_errors do
        humans = Slack::Client.list_users(workspace: @workspace)
          .reject { |user| user[:is_bot] || user[:id] == "USLACKBOT" }
        active, deactivated = humans.partition { |user| !user[:deleted] }

        members = active.map do |user|
          profile = user[:profile] || {}
          {
            id: user[:id],
            name: profile[:real_name].presence || profile[:display_name].presence || user[:name],
            avatarUrl: profile[:image_48]
          }
        end

        { members: members, deactivated_ids: deactivated.map { |user| user[:id] } }
      end
    end

    # Cached because pickers hit this several times per interaction and
    # conversations.list is Tier 2 rate limited.
    def list_channels
      Rails.cache.fetch("slack:channels:#{@workspace.id}", expires_in: 1.minute) do
        translate_errors do
          raw_channels = Slack::Client.list_conversations(workspace: @workspace)

          raw_channels.map do |c|
            { id: c[:id], name: c[:name] }
          end
        end
      end
    end

    private

    # The id and the name the reference carries, or nil for a bare name.
    def channel_reference(text)
      mention = text.match(CHANNEL_MENTION)
      return [ mention[1], mention[2] ] if mention

      link = text.match(CHANNEL_LINK)
      return [ link[1].upcase, nil ] if link

      text.match?(CHANNEL_ID) ? [ text, nil ] : nil
    end

    def translate_errors
      yield
    rescue AdapterError::AuthRevoked => e
      Slack::AuthRevokedNotifier.notify(@workspace, error_code: e.error_code)
      raise
    end

    # Something that only helps, such as a reaction already gone, never stops the work it goes with.
    def quietly(what)
      yield
    rescue AdapterError => e
      Rails.logger.info({ event: "slack.best_effort_skipped", what: what, error: e.message }.to_json)
      { success: false }
    end
  end
end
