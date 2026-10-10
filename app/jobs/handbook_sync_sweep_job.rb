# Every hour, reads again each source of synced handbook pages not read within the hour, so a document in a tool that
# sends no news, or a push that never arrived, still reaches the handbook.
class HandbookSyncSweepJob < ApplicationJob
  queue_as :default

  def perform = HandbookSync.sweep!
end
