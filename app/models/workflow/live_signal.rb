# Says which part of a workflow's page changed, once the change commits, so an open canvas reads that part again rather
# than asking the server every few seconds whether anything moved. The canvas part is the workflow, its versions, edits,
# Halon's suggestions and the requests to publish it. The runs part is its runs and their steps. Every record the page
# shows includes it and names its part, and a write that skips callbacks (a guarded update_all) calls
# signal_workflow_page itself once it wins. The model only says it happened, as an EVENT notification, and
# Workflow::LiveDelivery is what tells the pages.
module Workflow::LiveSignal
  extend ActiveSupport::Concern

  PART_CANVAS = "canvas"
  PART_RUNS = "runs"
  PARTS = { "CANVAS" => PART_CANVAS, "RUNS" => PART_RUNS }.freeze
  EVENT = "changed.workflow_page"

  class_methods do
    def shown_on_workflow_page(part)
      class_attribute :workflow_page_part, instance_writer: false, default: part
      after_commit :signal_workflow_page
    end
  end

  # Waits for the outermost transaction, so a change that rolls back is never announced.
  def self.signal!(workflow_id, part)
    return if workflow_id.blank?

    ActiveRecord.after_all_transactions_commit do
      ActiveSupport::Notifications.instrument(EVENT, workflow_id: workflow_id, part: part)
    end
  end

  def signal_workflow_page
    Workflow::LiveSignal.signal!(is_a?(Workflow) ? id : workflow_id, workflow_page_part)
  end
end
