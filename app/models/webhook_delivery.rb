class WebhookDelivery < ApplicationRecord
  STALE_THRESHOLD = 7.days

  belongs_to :webhook
  # What it is about: an incident's event, or the workflow run whose Send webhook step sent it.
  belongs_to :incident_event, optional: true
  belongs_to :workflow_run, class_name: "Workflow::Run", optional: true

  validate :about_something

  # Set by a step that sends the delivery itself and waits for its answer, so no job sends it too.
  attribute :sent_by_caller, :boolean, default: false

  # Decided once where the response is known, so no reader recomputes the
  # outcome from other columns.
  enum :state, { pending: "pending", in_progress: "in_progress", succeeded: "succeeded", failed: "failed" }, default: :pending

  scope :ordered, -> { order(created_at: :desc, id: :desc) }
  scope :stale, -> { where(created_at: ...STALE_THRESHOLD.ago) }

  after_create_commit :deliver_later

  # Longer than a delivery and its retries take, so one still unsent after it lost its job to a stopped worker.
  UNSENT_AFTER = 1.hour
  INTERRUPTED = "interrupted".freeze

  # Ends a delivery whose job will not run again, once, saying so on the webhook's delivery list.
  def self.give_up_interrupted!(scope = where(updated_at: ...UNSENT_AFTER.ago))
    scope.where(state: [ states[:pending], states[:in_progress] ]).update_all(state: states[:failed], error_message: INTERRUPTED, updated_at: Time.current)
  end

  def self.cleanup(batch_size: 500, pause: 0.1)
    BatchedDelete.run(
      stale,
      label: "webhook_deliveries.cleanup",
      batch_size: batch_size,
      pause: pause,
      metadata: { stale_days: STALE_THRESHOLD.to_i / 86_400 }
    )
  end

  # A fresh row so the replay has its own audit trail, carrying the original
  # bytes so it sends what was sent before rather than re-rendering.
  def replay!
    self.class.create!(
      webhook: webhook,
      incident_event: incident_event,
      workflow_run: workflow_run,
      event_type: event_type,
      signed_payload: signed_payload
    )
  end

  private

  def deliver_later
    Webhooks::DeliveryJob.perform_later(self) unless sent_by_caller
  end

  def about_something
    errors.add(:base, "A delivery is about an incident's event or a workflow run.") if incident_event_id.nil? && workflow_run_id.nil?
  end
end
