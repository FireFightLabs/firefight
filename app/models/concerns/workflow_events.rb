# frozen_string_literal: true

# WorkflowEvents - Centralized constants for all workflow event types
#
# This module defines all event types used throughout the workflow system.
# Using constants prevents typos and enables IDE autocomplete.
#
# Event naming convention: <scope>.<action>
# - Scopes: workflow (workflow-level), step (step-level)
# - Actions: past tense for completed actions, present/descriptive for states
#
# Usage:
#   record_event(WorkflowEvents::Workflow::SUCCEEDED)
#   record_event(WorkflowEvents::Step::STARTED, step: self)
#
module WorkflowEvents
  # Workflow-level events
  module Workflow
    STARTED = "workflow.started"
    RUNNING = "workflow.running"
    SUCCEEDED = "workflow.succeeded"
    FAILED = "workflow.failed"
    CANCELLED = "workflow.cancelled"
    PAUSED = "workflow.paused"
    RESUMED = "workflow.resumed"
  end

  # Step-level events
  module Step
    STARTED = "step.started"
    SUCCEEDED = "step.succeeded"
    FAILED = "step.failed"
    SKIPPED = "step.skipped"
    CANCELLED = "step.cancelled"
    RETRY_SCHEDULED = "step.retry_scheduled"
    MANUAL_RETRY = "step.manual_retry"
    MANUAL_SKIP = "step.manual_skip"
    RESET = "step.reset"
  end
end
