# How a draft becomes live, is thrown away, or comes back from an older version. Each move is one guarded update on the
# status it leaves, so two people pressing at once move it once.
module Workflow::Version::Publishing
  extend ActiveSupport::Concern

  # Why it cannot be published, as a sentence, or nil.
  def publish_blocked_reason
    return "Only a draft can be published." unless draft?

    found = problems
    found.any? ? "It cannot be published yet. #{found.first}" : nil
  end

  # Publishes what the publisher saw, so a draft changed since they looked is left for them to look at again.
  def publish!(by:, revision: self.revision)
    blocked = publish_blocked_reason
    raise Workflow::Edit::Refused, blocked if blocked

    published = transaction do
      self.class.where(workflow_id: workflow_id, status: Workflow::Version::STATUS_LIVE)
                .update_all(status: Workflow::Version::STATUS_RETIRED, updated_at: Time.current)
      moved = self.class.where(id: id, status: Workflow::Version::STATUS_DRAFT, revision: revision)
                        .update_all(status: Workflow::Version::STATUS_LIVE, published_at: Time.current, published_by_id: by&.id, updated_at: Time.current)
      raise ActiveRecord::Rollback unless moved == 1

      Workflow.where(id: workflow_id).update_all(live_version_id: id, updated_at: Time.current)
      signal_workflow_page
      true
    end
    raise Workflow::Edit::Refused, "Someone changed the draft since you looked, so look again before publishing." unless published

    reload
    workflow.reload
    self
  end

  def discard!
    moved = self.class.where(id: id, status: Workflow::Version::STATUS_DRAFT)
                      .update_all(status: Workflow::Version::STATUS_DISCARDED, updated_at: Time.current)
    raise Workflow::Edit::Refused, "Only a draft can be thrown away." unless moved == 1

    signal_workflow_page
    reload
  end

  def restore_blocked_reason
    return "This is already the draft." if draft?
    return "Publish or discard the open draft first." if workflow.draft

    nil
  end

  # A new draft holding this version's content. History is never rewritten.
  def restore!(by:, halon: false, reason: nil)
    blocked = restore_blocked_reason
    raise Workflow::Edit::Refused, blocked if blocked

    workflow.open_draft!(from: self, by: by, halon: halon, reason: reason || "Restored version #{number}.")
  end
end
