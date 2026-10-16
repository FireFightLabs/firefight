# Whether a workspace's Slack draws the newer blocks (Slack::Blocks::KINDS). Slack answers a block it does not draw with
# invalid_blocks, which the client raises as AdapterError::Unrenderable. The message then goes plain at once, and the
# refusal is remembered on the workspace for each kind the message used (platform_data["<kind>_blocks_refused_at"]), so
# later messages of that kind go plain without asking until RETRY_RICH_BLOCKS_AFTER has passed, in case the workspace
# changed plans. A kind is remembered alone, so a refused alert never takes cards with it.
module Slack::WorkspaceAdapter::RichBlocks
  extend ActiveSupport::Concern

  RETRY_RICH_BLOCKS_AFTER = 7.days

  private

  # Yields true when every kind the message uses may be drawn rich, and draws the same message plainly when Slack
  # refuses it. The block posts or updates, and whatever it returns is returned.
  #
  #   with_rich_blocks(Slack::Blocks::CARD) { |rich| post_message(channel_id: id, text: text, blocks: card.to_blocks(rich: rich)) }
  def with_rich_blocks(*kinds)
    if kinds.all? { |kind| rich_blocks?(kind) }
      begin
        return yield(true)
      rescue AdapterError::Unrenderable => error
        Rails.logger.info({ event: "slack.rich_blocks_refused", workspace_id: @workspace.id, kinds: kinds, error: error.message }.to_json)
        kinds.each { |kind| rich_blocks_refused!(kind) }
      end
    end
    yield(false)
  end

  def with_plan_blocks(&) = with_rich_blocks(Slack::Blocks::PLAN, &)

  def rich_blocks?(kind)
    refused = @workspace.platform_data.to_h[rich_blocks_key(kind)]
    refused.blank? || Time.zone.parse(refused.to_s) < RETRY_RICH_BLOCKS_AFTER.ago
  end

  def rich_blocks_refused!(kind)
    key = rich_blocks_key(kind)
    now = Time.current.iso8601
    Workspace.where(id: @workspace.id)
             .update_all([ "platform_data = COALESCE(platform_data, '{}'::jsonb) || jsonb_build_object(?::text, ?::text)", key, now ])
    @workspace.platform_data = @workspace.platform_data.to_h.merge(key => now)
  end

  def rich_blocks_key(kind)
    raise ArgumentError, "Unknown block kind #{kind.inspect}" unless Slack::Blocks::KINDS.include?(kind)

    "#{kind}_blocks_refused_at"
  end
end
