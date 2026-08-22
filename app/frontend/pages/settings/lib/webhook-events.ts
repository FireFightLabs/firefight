// Mirrors Webhook::SUBSCRIBABLE_EVENTS, in the same order. A Ruby test fails
// if the two drift, because this list is what a customer can actually pick and
// the server accepting an event nobody can subscribe to helps no one.
export const subscribableEvents = [
  { value: "incident.created", label: "Incident created" },
  { value: "incident.updated", label: "Incident updated" },
  { value: "incident.accepted", label: "Incident accepted" },
  { value: "incident.resolved", label: "Incident resolved" },
  { value: "incident.reopened", label: "Incident reopened" },
  { value: "incident.canceled", label: "Incident canceled" },
  { value: "incident.escalated", label: "Incident escalated" },
  { value: "lead.assigned", label: "Lead assigned" },
  { value: "role.assigned", label: "Role assigned" },
  { value: "role.unassigned", label: "Role unassigned" },
  { value: "action.created", label: "Action created" },
  { value: "action.picked_up", label: "Action picked up" },
  { value: "action.completed", label: "Action completed" },
  { value: "action.reassigned", label: "Action reassigned" },
  { value: "runbook.attached", label: "Runbook attached" },
  { value: "postmortem.generated", label: "Postmortem generated" },
  { value: "postmortem.edited", label: "Postmortem edited" },
  { value: "relationship.created", label: "Relationship created" },
  { value: "incident.marked_duplicate", label: "Incident marked duplicate" },
  { value: "incident.merged_into", label: "Incident merged into" },
] as const

export const eventLabel = (value: string) =>
  subscribableEvents.find((event) => event.value === value)?.label ?? value
