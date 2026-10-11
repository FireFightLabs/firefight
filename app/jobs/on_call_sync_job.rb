# Takes a change made here to a page in its on-call tool, or raises a page an approver let through, as Firefight paging.
# by is whoever's change it was, which the ledger names.
class OnCallSyncJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(operation:, page:, by:, approval_id: nil)
    OnCallSyncService.new(page.workspace).perform(operation, page, by, approval_id: approval_id)
  end
end
