import type { WorkflowTriggerKind } from "@/lib/generated/constants"

// What starts a workflow, as a person reads it.
export const WORKFLOW_TRIGGER_LABELS: Record<WorkflowTriggerKind, string> = {
  manual: "Run by hand",
  schedule: "On a schedule",
  once_at: "Once, at a time",
  incident_declared: "When an incident is declared",
  incident_changed: "When an incident changes",
  alert_received: "When an alert arrives",
  inbound_webhook: "When its webhook is called",
  deploy_finished: "When a deploy or CI run finishes",
  resource_changed: "When a resource changes",
  service_scaled: "When a service scales",
  security_event: "On a security event",
  notice_raised: "When Halon raises a notice",
  investigation_finished: "When an investigation finishes",
  follow_up_changed: "When a follow-up or postmortem changes",
  issue_assigned: "When an issue is assigned to Firefight",
  run_failed: "When another workflow's run fails",
  called: "When another workflow runs it",
}
