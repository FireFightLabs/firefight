export const subscribableEvents = [
  { value: "incident.created", label: "Incident created" },
  { value: "incident.updated", label: "Incident updated" },
  { value: "incident.resolved", label: "Incident resolved" },
  { value: "incident.reopened", label: "Incident reopened" },
  { value: "incident.escalated", label: "Incident escalated" },
  { value: "lead.assigned", label: "Lead assigned" },
  { value: "action.created", label: "Action created" },
  { value: "action.picked_up", label: "Action picked up" },
  { value: "action.completed", label: "Action completed" },
  { value: "runbook.attached", label: "Runbook attached" },
  { value: "runbook.applied", label: "Runbook applied" },
  { value: "postmortem.generated", label: "Postmortem generated" },
  { value: "relationship.created", label: "Relationship created" },
  { value: "incident.marked_duplicate", label: "Incident marked duplicate" },
  { value: "incident.merged_into", label: "Incident merged into" },
] as const

export const eventLabel = (value: string) =>
  subscribableEvents.find((e) => e.value === value)?.label ?? value
