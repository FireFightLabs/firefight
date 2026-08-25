# A permalink is decoration on an event's metadata, so failing to fetch one
# never fails the event. Lives here rather than under app/services/events/
# because the milestone pass wants it too, and a handler is not a library.
module MessagePermalinks
  def self.fetch(workspace, channel_id, message_ts)
    workspace.adapter.get_message_permalink(channel_id: channel_id, message_id: message_ts)[:permalink]
  rescue AdapterError
    nil
  end
end
