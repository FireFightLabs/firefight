# Reads one source of synced handbook pages and writes its pages. One source is read by one worker at a time, so a push
# and the sweep never both write the same pages.
class HandbookSyncJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  limits_concurrency to: 1, key: ->(source_id) { "handbook_sync:#{source_id}" }

  def perform(source_id)
    HandbookSync.new(Chat::HandbookSource.find(source_id)).sync!
  end
end
