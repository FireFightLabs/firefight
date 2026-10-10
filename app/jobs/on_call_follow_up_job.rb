# What Halon does on its own once a run an alert started has answered: apply a fix the team allowed ahead, then page
# whoever it found on call with what it found and what it did. Each claims its own row, so a retry never does either twice.
class OnCallFollowUpJob < ApplicationJob
  queue_as :default
  discard_on ActiveRecord::RecordNotFound

  def perform(investigation_id)
    investigation = Investigation.find(investigation_id)
    Investigation::Unattended.consider!(investigation)
    Investigation::Paging.page!(investigation)
  end
end
