# One check of one watch, from the sweep or at once when a connection it reads says something changed. A watch another
# worker is checking is left to it (Chat::Watch#claim_check!).
class WatchCheckJob < ApplicationJob
  queue_as :background

  def perform(watch_id)
    watch = Chat::Watch.find_by(id: watch_id)
    Conversation::Watches.check!(watch) if watch
  end
end
