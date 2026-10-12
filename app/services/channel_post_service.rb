# Posts a message as Firefight in a channel someone named, such as release notes in #general. The caller authorized it
# as channel_posts.create, so this only finds the channel, posts and says where. Every way it can fail is a sentence
# the person or Halon can act on, such as inviting Firefight to a private channel.
class ChannelPostService
  MESSAGE_LIMIT = 10_000

  Posted = Data.define(:channel_id, :channel_name, :link)

  class Refused < StandardError; end

  def initialize(workspace)
    @workspace = workspace
  end

  def post!(channel:, message:, by:, by_halon: false)
    named = channel.to_s.strip
    raise Refused, "Say which channel to post in, by its name or its link." if named.empty?
    raise Refused, "Say what to post." if message.to_s.strip.empty?
    raise Refused, "The message is longer than #{MESSAGE_LIMIT.to_fs(:delimited)} characters. Shorten it, or post it in parts." if message.length > MESSAGE_LIMIT

    found = adapter.find_channel(reference: named)
    posted = adapter.post_channel_message(channel_id: found[:channel_id], message: message.strip, posted_by: by, by_halon: by_halon)
    Posted.new(channel_id: posted[:channel_id] || found[:channel_id], channel_name: found[:channel_name], link: link_to(found[:channel_id], posted[:message_id]))
  rescue AdapterError => error
    raise Refused, refusal(error, named)
  end

  private

  def adapter = @adapter ||= WorkspaceAdapter.for(@workspace)

  def refusal(error, named)
    shown = shown(named)
    case error
    when AdapterError::NotFound
      "Firefight cannot see #{shown}. Check the name. If it is a private channel, invite Firefight to it, then name it by its link."
    when AdapterError::NotInChannel
      "Firefight is not in #{shown}, so it cannot post there. Invite Firefight to the channel, then ask again."
    when AdapterError::IsArchived then "#{shown.upcase_first} is archived, so nothing can be posted there."
    when AdapterError::RestrictedAction then "Only some people may post in #{shown}, and Firefight is not one of them."
    when AdapterError::NotConnected then "This workspace has not connected a chat platform yet, so there is nowhere to post."
    else "Firefight could not post in #{shown} just now. Try again in a minute."
    end
  end

  # A name reads as #name, written with its # or in lower case as channel names are. An id, a mention or a link reads
  # as the channel.
  def shown(named)
    plain = named.delete_prefix("#")
    name = plain.match?(/\A[a-z0-9][a-z0-9._-]*\z/i) && (named.start_with?("#") || plain == plain.downcase)
    name ? "##{plain.downcase}" : "that channel"
  end

  # The link is a courtesy, so a post that went through is never reported as failed for want of one.
  def link_to(channel_id, message_id)
    return nil if message_id.blank?

    adapter.get_message_permalink(channel_id: channel_id, message_id: message_id)[:permalink]
  rescue AdapterError
    nil
  end
end
